use std::fs::{self, File};
use std::io;
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicUsize, Ordering};

use zip::write::SimpleFileOptions;
use zip::ZipWriter;

use crate::tcr::decompress_tcr;

const CREATE_NO_WINDOW: u32 = 0x0800_0000;
const MAX_COMIC_BYTES: u64 = 512 * 1024 * 1024;
const MAX_COMIC_PAGES: usize = 10_000;
static TEMP_COUNTER: AtomicUsize = AtomicUsize::new(0);

fn is_comic_image(path: &Path) -> bool {
    matches!(
        path.extension()
            .and_then(|ext| ext.to_str())
            .map(|ext| ext.to_ascii_lowercase())
            .as_deref(),
        Some(
            "jpg"
                | "jpeg"
                | "jfif"
                | "png"
                | "gif"
                | "bmp"
                | "webp"
                | "tif"
                | "tiff"
                | "avif"
                | "jxl"
                | "jp2"
                | "j2k"
                | "svg"
        )
    )
}

pub struct PreparedDocument {
    pub file_path: PathBuf,
    pub display_name: String,
    pub mime_type: &'static str,
    temp_dir: Option<PathBuf>,
}

impl PreparedDocument {
    pub fn direct(file_path: PathBuf) -> Self {
        let display_name = file_path
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_else(|| file_path.display().to_string());
        let mime_type = match file_path
            .extension()
            .and_then(|ext| ext.to_str())
            .map(|ext| ext.to_ascii_lowercase())
            .as_deref()
        {
            Some("epub") => "application/epub+zip",
            Some("mobi") => "application/x-mobipocket-ebook",
            Some("azw") | Some("azw3") => "application/vnd.amazon.ebook",
            Some("fb2") => "application/x-fictionbook+xml",
            Some("fbz") => "application/x-zip-compressed-fb2",
            Some("cbz") => "application/vnd.comicbook+zip",
            Some("pdf") => "application/pdf",
            _ => "application/octet-stream",
        };

        Self {
            file_path,
            display_name,
            mime_type,
            temp_dir: None,
        }
    }

    pub fn temporary(
        file_path: PathBuf,
        display_name: String,
        mime_type: &'static str,
        temp_dir: PathBuf,
    ) -> Self {
        Self {
            file_path,
            display_name,
            mime_type,
            temp_dir: Some(temp_dir),
        }
    }
}

impl Drop for PreparedDocument {
    fn drop(&mut self) {
        if let Some(ref dir) = self.temp_dir {
            let _ = fs::remove_dir_all(dir);
        }
    }
}

fn create_temp_directory(purpose: &str) -> io::Result<PathBuf> {
    let pid = std::process::id();
    let id = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
    let dir = std::env::temp_dir()
        .join("Inf-Dir")
        .join("ebook-view")
        .join(format!("{purpose}-{pid}-{id}"));
    fs::create_dir_all(&dir)?;
    Ok(dir)
}

fn find_on_path(executable: &str) -> Option<PathBuf> {
    let path_var = std::env::var_os("PATH")?;
    for dir in std::env::split_paths(&path_var) {
        let candidate = dir.join(executable);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

/// Directory of this viewer's own source tree, searched while developing so the
/// viewer can be launched from `target\release` without staging the runtime.
const VIEWER_DIR_NAME: &str = "ebook-view";

/// Package that carries runtimes shared by more than one viewer, installed
/// beside the viewer packages in `plugins\dist\`.
const SHARED_RUNTIME_PACKAGE: &str = "inf-dir.runtime";

/// Plain `runtime\` directory holding the same shared runtimes. The source
/// tree uses this layout before `plugins\build.bat` installs the package.
const SHARED_RUNTIME_DIR: &str = "runtime";

/// How many parent directories are inspected when looking for a runtime.
const RUNTIME_SEARCH_DEPTH: usize = 8;

fn push_unique(roots: &mut Vec<PathBuf>, root: PathBuf) {
    if !roots.contains(&root) {
        roots.push(root);
    }
}

/// Directories that may contain a runtime, ordered from the most specific (a
/// copy shipped inside this package) to the most general (a shared runtime
/// prepared in the source tree).
///
/// The shared package is looked up both beside this package
/// (`plugins\dist\inf-dir.runtime\`) and at every ancestor level, which covers
/// the development layout where the executable sits several directories below
/// the repository's `plugins\` directory.
fn runtime_search_roots() -> Vec<PathBuf> {
    let mut roots = Vec::new();
    let Ok(current_exe) = std::env::current_exe() else {
        return roots;
    };
    let Some(exe_dir) = current_exe.parent() else {
        return roots;
    };

    push_unique(&mut roots, exe_dir.to_path_buf());
    let mut ancestor = Some(exe_dir);
    for _ in 0..RUNTIME_SEARCH_DEPTH {
        let Some(directory) = ancestor else { break };
        push_unique(&mut roots, directory.join(SHARED_RUNTIME_PACKAGE));
        push_unique(&mut roots, directory.join(SHARED_RUNTIME_DIR));
        push_unique(&mut roots, directory.join(VIEWER_DIR_NAME));
        ancestor = directory.parent();
    }
    roots
}

/// Locate `<directory>\<executable>` under one of [`runtime_search_roots`].
fn find_runtime_tool(directory: &str, executable: &str) -> Option<PathBuf> {
    runtime_search_roots()
        .into_iter()
        .map(|root| root.join(directory).join(executable))
        .find(|candidate| candidate.is_file())
}

/// DjVuLibre used to ship inside the `mupdf-view` package. Keep resolving that
/// location so an already installed `plugins\dist\` tree keeps working without
/// a rebuild; drop this once the shared runtime package is the only layout in
/// the wild.
fn find_legacy_mupdf_djvulibre() -> Option<PathBuf> {
    let current_exe = std::env::current_exe().ok()?;
    let packages_dir = current_exe.parent()?.parent()?;
    ["inf-dir.mupdf-view", "mupdf-view"]
        .into_iter()
        .map(|name| {
            packages_dir
                .join(name)
                .join("djvulibre")
                .join("ddjvu.exe")
        })
        .find(|candidate| candidate.is_file())
}

fn find_djvulibre() -> Option<PathBuf> {
    if let Ok(path) = std::env::var("INF_DIR_DJVULIBRE_PATH") {
        let configured = PathBuf::from(path);
        if configured.is_file() {
            return Some(configured);
        }
        if configured.is_dir() {
            let nested = configured.join("ddjvu.exe");
            if nested.is_file() {
                return Some(nested);
            }
        }
    }
    find_runtime_tool("djvulibre", "ddjvu.exe")
        .or_else(find_legacy_mupdf_djvulibre)
        .or_else(|| find_on_path("ddjvu.exe"))
}

/// `gxpswin64.exe` turns XPS/OpenXPS into PDF. It lives in the shared runtime
/// package because XPS is the one page-document format that neither foliate-js
/// nor the PDF viewers can read natively.
fn find_gxps() -> Option<PathBuf> {
    if let Ok(path) = std::env::var("INF_DIR_GXPS_PATH") {
        let configured = PathBuf::from(path);
        if configured.is_file() {
            return Some(configured);
        }
        if configured.is_dir() {
            let nested = configured.join("gxpswin64.exe");
            if nested.is_file() {
                return Some(nested);
            }
        }
    }
    find_runtime_tool("gxps", "gxpswin64.exe").or_else(|| find_on_path("gxpswin64.exe"))
}

fn find_comic_extractor() -> Option<PathBuf> {
    if let Ok(path) = std::env::var("INF_DIR_ARCHIVE_VIEW_PATH") {
        let p = PathBuf::from(path);
        if p.is_file() {
            return Some(p);
        }
    }
    if let Ok(current_exe) = std::env::current_exe() {
        if let Some(parent) = current_exe.parent() {
            let candidates = [
                parent.join("archive-view.exe"),
                parent.join("..").join("inf-dir.archive-view").join("archive-view.exe"),
                parent.join("..").join("archive-view").join("archive-view.exe"),
            ];
            for candidate in candidates {
                if candidate.is_file() {
                    return Some(candidate);
                }
            }
        }
    }
    // Fallback to 7-zip if available
    find_seven_zip()
}

fn find_seven_zip() -> Option<PathBuf> {
    if let Ok(path) = std::env::var("INF_DIR_7Z_PATH") {
        let p = PathBuf::from(path);
        if p.is_file() {
            return Some(p);
        }
    }
    if let Ok(current_exe) = std::env::current_exe() {
        if let Some(parent) = current_exe.parent() {
            let candidates = [
                parent.join("7za.exe"),
                parent.join("..").join("inf-dir.7z-archive").join("7za.exe"),
                parent.join("..").join("7z-archive").join("7za.exe"),
            ];
            for candidate in candidates {
                if candidate.is_file() {
                    return Some(candidate);
                }
            }
        }
    }
    find_on_path("7za.exe").or_else(|| find_on_path("7z.exe"))
}

fn run_tool(executable: &Path, args: &[&str]) -> io::Result<Output> {
    let mut command = Command::new(executable);
    command.args(args);
    command.creation_flags(CREATE_NO_WINDOW);
    command.output()
}

pub fn prepare_document(source: &Path) -> Result<PreparedDocument, String> {
    let ext = source
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase())
        .unwrap_or_default();

    let display_name = source
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| source.display().to_string());

    match ext.as_str() {
        "djvu" | "djv" => convert_djvu(source, display_name),
        "xps" | "oxps" => convert_xps(source, display_name),
        "tcr" => convert_tcr(source, display_name),
        "cbr" => convert_cbr(source, display_name),
        _ => Ok(PreparedDocument::direct(source.to_path_buf())),
    }
}

/// XPS and OpenXPS are converted to PDF with the shared GhostXPS interpreter;
/// the resulting PDF keeps the vector content, and is rendered by foliate-js'
/// bundled pdf.js like every other PDF in this viewer.
fn convert_xps(source: &Path, display_name: String) -> Result<PreparedDocument, String> {
    let gxps = find_gxps().ok_or_else(|| {
        "XPS viewing requires the shared GhostXPS runtime. Run plugins\\build.bat to install the shared runtime package, or set INF_DIR_GXPS_PATH."
            .to_string()
    })?;

    let temp_dir = create_temp_directory("xps")
        .map_err(|e| format!("Failed to create temporary directory for XPS: {e}"))?;
    let stem = source.file_stem().and_then(|s| s.to_str()).unwrap_or("document");
    let output_pdf = temp_dir.join(format!("{stem}.pdf"));

    let source_str = source.to_string_lossy();
    let output_arg = format!("-o{}", output_pdf.to_string_lossy());
    let result = run_tool(
        &gxps,
        &[
            "-q",
            "-dNOPAUSE",
            "-dBATCH",
            "-sDEVICE=pdfwrite",
            output_arg.as_str(),
            source_str.as_ref(),
        ],
    );

    let output = match result {
        Ok(output) => output,
        Err(error) => {
            let _ = fs::remove_dir_all(&temp_dir);
            return Err(format!("Failed to execute gxps: {error}"));
        }
    };

    if !output.status.success() || !output_pdf.is_file() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        let detail = if stderr.trim().is_empty() { stdout } else { stderr };
        let _ = fs::remove_dir_all(&temp_dir);
        return Err(format!("XPS to PDF conversion failed: {}", detail.trim()));
    }

    Ok(PreparedDocument::temporary(
        output_pdf,
        display_name,
        "application/pdf",
        temp_dir,
    ))
}

fn convert_djvu(source: &Path, display_name: String) -> Result<PreparedDocument, String> {
    let ddjvu = find_djvulibre().ok_or_else(|| {
        "DjVu viewing requires DjVuLibre (ddjvu.exe). Run plugins\\build.bat to install the shared runtime package, or set INF_DIR_DJVULIBRE_PATH."
            .to_string()
    })?;

    let temp_dir = create_temp_directory("djvu")
        .map_err(|e| format!("Failed to create temporary directory for DjVu: {e}"))?;
    let stem = source.file_stem().and_then(|s| s.to_str()).unwrap_or("book");
    let output_pdf = temp_dir.join(format!("{stem}.pdf"));

    let source_str = source.to_string_lossy();
    let output_str = output_pdf.to_string_lossy();
    let output = run_tool(
        &ddjvu,
        &["-format=pdf", source_str.as_ref(), output_str.as_ref()],
    )
    .map_err(|e| format!("Failed to execute ddjvu: {e}"))?;

    if !output.status.success() || !output_pdf.is_file() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("DjVu to PDF conversion failed: {stderr}"));
    }

    Ok(PreparedDocument::temporary(
        output_pdf,
        display_name,
        "application/pdf",
        temp_dir,
    ))
}

fn convert_tcr(source: &Path, display_name: String) -> Result<PreparedDocument, String> {
    let bytes = fs::read(source).map_err(|e| format!("Failed to read TCR file: {e}"))?;
    let html = decompress_tcr(&bytes).map_err(|e| format!("TCR decompression failed: {e}"))?;

    let temp_dir = create_temp_directory("tcr")
        .map_err(|e| format!("Failed to create temporary directory for TCR: {e}"))?;
    let stem = source.file_stem().and_then(|s| s.to_str()).unwrap_or("book");
    let output_html = temp_dir.join(format!("{stem}.html"));

    fs::write(&output_html, html.as_bytes())
        .map_err(|e| format!("Failed to write decompressed TCR HTML: {e}"))?;

    Ok(PreparedDocument::temporary(
        output_html,
        display_name,
        "text/html; charset=utf-8",
        temp_dir,
    ))
}

fn convert_cbr(source: &Path, display_name: String) -> Result<PreparedDocument, String> {
    let extractor = find_comic_extractor().ok_or_else(|| {
        "CBR comic preview requires archive-view or 7-Zip. Run plugins\\build.bat first."
            .to_string()
    })?;

    let temp_dir = create_temp_directory("cbr")
        .map_err(|e| format!("Failed to create temporary directory for CBR: {e}"))?;
    let extracted_dir = temp_dir.join("extracted");
    fs::create_dir_all(&extracted_dir)
        .map_err(|e| format!("Failed to create extraction folder: {e}"))?;

    let is_archive_view = extractor
        .file_name()
        .and_then(|n| n.to_str())
        .map(|n| n.eq_ignore_ascii_case("archive-view.exe"))
        .unwrap_or(false);

    let source_str = source.to_string_lossy();
    let extracted_str = extracted_dir.to_string_lossy();

    let output = if is_archive_view {
        run_tool(
            &extractor,
            &["--extract-comic", source_str.as_ref(), extracted_str.as_ref()],
        )
    } else {
        let out_arg = format!("-o{}", extracted_str);
        run_tool(
            &extractor,
            &["x", source_str.as_ref(), &out_arg, "-y", "-aoa"],
        )
    }
    .map_err(|e| format!("Failed to run comic extractor: {e}"))?;

    if !output.status.success() {
        let err = String::from_utf8_lossy(&output.stderr);
        let out = String::from_utf8_lossy(&output.stdout);
        let msg = if !err.trim().is_empty() { err } else { out };
        return Err(format!("CBR extraction failed: {msg}"));
    }

    // Collect images and sort them naturally
    let mut image_files = Vec::new();
    collect_images(&extracted_dir, &mut image_files)?;

    if image_files.is_empty() {
        return Err("CBR archive contains no supported comic images".to_string());
    }

    image_files.sort_by(|a, b| natord::compare(&a.to_string_lossy(), &b.to_string_lossy()));

    // Package into a temporary .cbz (ZIP)
    let stem = source.file_stem().and_then(|s| s.to_str()).unwrap_or("comic");
    let output_cbz = temp_dir.join(format!("{stem}.cbz"));
    let zip_file = File::create(&output_cbz)
        .map_err(|e| format!("Failed to create temporary CBZ archive: {e}"))?;
    let mut zip = ZipWriter::new(zip_file);
    let options = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);

    let mut total_bytes = 0u64;
    for (index, image_path) in image_files.iter().enumerate() {
        if index >= MAX_COMIC_PAGES {
            break;
        }
        let ext = image_path
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("jpg");
        let entry_name = format!("page_{:05}.{ext}", index + 1);
        let mut f = File::open(image_path)
            .map_err(|e| format!("Failed to open extracted image page: {e}"))?;
        let metadata = f
            .metadata()
            .map_err(|e| format!("Failed to query image page metadata: {e}"))?;

        total_bytes = total_bytes
            .checked_add(metadata.len())
            .ok_or_else(|| "CBR image data size overflow".to_string())?;
        if total_bytes > MAX_COMIC_BYTES {
            return Err("CBR image data exceeds 512 MiB safety limit".to_string());
        }

        zip.start_file(entry_name, options)
            .map_err(|e| format!("Failed to add image to CBZ: {e}"))?;
        io::copy(&mut f, &mut zip)
            .map_err(|e| format!("Failed writing image to CBZ: {e}"))?;
    }

    zip.finish()
        .map_err(|e| format!("Failed to finalize CBZ archive: {e}"))?;

    Ok(PreparedDocument::temporary(
        output_cbz,
        display_name,
        "application/vnd.comicbook+zip",
        temp_dir,
    ))
}

fn collect_images(dir: &Path, list: &mut Vec<PathBuf>) -> Result<(), String> {
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                collect_images(&path, list)?;
            } else if path.is_file() && is_comic_image(&path) {
                list.push(path);
            }
        }
    }
    Ok(())
}

mod natord {
    use std::cmp::Ordering;

    pub fn compare(a: &str, b: &str) -> Ordering {
        let mut a_chars = a.chars().peekable();
        let mut b_chars = b.chars().peekable();

        loop {
            match (a_chars.peek(), b_chars.peek()) {
                (None, None) => return Ordering::Equal,
                (None, Some(_)) => return Ordering::Less,
                (Some(_), None) => return Ordering::Greater,
                (Some(ca), Some(cb)) if ca.is_ascii_digit() && cb.is_ascii_digit() => {
                    let mut a_num = 0u64;
                    while let Some(c) = a_chars.peek() {
                        if let Some(digit) = c.to_digit(10) {
                            a_num = a_num.saturating_mul(10).saturating_add(digit as u64);
                            a_chars.next();
                        } else {
                            break;
                        }
                    }
                    let mut b_num = 0u64;
                    while let Some(c) = b_chars.peek() {
                        if let Some(digit) = c.to_digit(10) {
                            b_num = b_num.saturating_mul(10).saturating_add(digit as u64);
                            b_chars.next();
                        } else {
                            break;
                        }
                    }
                    if a_num != b_num {
                        return a_num.cmp(&b_num);
                    }
                }
                (Some(&ca), Some(&cb)) => {
                    let ord = ca.to_ascii_lowercase().cmp(&cb.to_ascii_lowercase());
                    if ord != Ordering::Equal {
                        return ord;
                    }
                    a_chars.next();
                    b_chars.next();
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn natord_sorts_correctly() {
        let mut list = vec!["page_10.jpg", "page_1.jpg", "page_2.jpg", "page_20.jpg"];
        list.sort_by(|a, b| natord::compare(a, b));
        assert_eq!(list, vec!["page_1.jpg", "page_2.jpg", "page_10.jpg", "page_20.jpg"]);
    }

    #[test]
    fn direct_document_mime() {
        let doc = PreparedDocument::direct(PathBuf::from("my_book.epub"));
        assert_eq!(doc.mime_type, "application/epub+zip");
    }

    #[test]
    fn runtime_roots_start_at_the_executable_and_offer_the_shared_layouts() {
        let roots = runtime_search_roots();
        let exe_dir = std::env::current_exe()
            .unwrap()
            .parent()
            .unwrap()
            .to_path_buf();

        // A runtime copied next to the executable wins over every shared copy.
        assert_eq!(roots.first(), Some(&exe_dir));
        // Both shared layouts are reachable: the installed package and the
        // source tree directory.
        assert!(roots.iter().any(|root| root.ends_with(SHARED_RUNTIME_PACKAGE)));
        assert!(roots.iter().any(|root| root.ends_with(SHARED_RUNTIME_DIR)));
        // The viewer's own source directory is searched too.
        assert!(roots.iter().any(|root| root.ends_with(VIEWER_DIR_NAME)));
    }

    #[test]
    fn runtime_search_roots_are_unique() {
        let roots = runtime_search_roots();
        let unique: std::collections::HashSet<_> = roots.iter().collect();
        assert_eq!(roots.len(), unique.len());
    }
}
