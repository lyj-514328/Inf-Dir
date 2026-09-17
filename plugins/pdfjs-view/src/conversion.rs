use std::fs;
use std::io;
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;
use std::time::{Duration, Instant};

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// LibreOffice headless conversion needs a warm-up on the first run; keep the
/// same ceiling the retired MuPDF viewer used.
const CONVERT_TIMEOUT: Duration = Duration::from_secs(120);
const POLL_INTERVAL: Duration = Duration::from_millis(50);

static TEMP_COUNTER: AtomicUsize = AtomicUsize::new(0);

/// Extension of this viewer's own source tree, searched while developing so
/// the viewer can run from `target\release` without staging the runtime.
const VIEWER_DIR_NAME: &str = "pdfjs-view";

/// Package that carries runtimes shared by more than one viewer, installed
/// beside the viewer packages in `plugins\dist\`.
const SHARED_RUNTIME_PACKAGE: &str = "inf-dir.runtime";

/// Plain `runtime\` directory holding the same shared runtimes. The source
/// tree uses this layout before `plugins\build.bat` installs the package.
const SHARED_RUNTIME_DIR: &str = "runtime";

/// How many parent directories are inspected when looking for a runtime.
const RUNTIME_SEARCH_DEPTH: usize = 8;

/// Formats pdf.js renders directly.
pub const NATIVE_EXTENSIONS: [&str; 1] = ["pdf"];

/// Filter passed to `soffice --convert-to`, i.e. the intermediate format every
/// document below is converted to before rendering.
const CONVERSION_FILTER: &str = "pdf";

/// Word-processing, presentation, spreadsheet (fallback), CAD and web-archive
/// formats that need LibreOffice before pdf.js can display them.
const SOFFICE_EXTENSIONS: [&str; 37] = [
    "doc", "docm", "docx", "dot", "dotm", "dotx", "odt", "ott", "fodt", "rtf", "wps", "wbk",
    "mht", "mhtml", "ppt", "pptm", "pptx", "pot", "potm", "potx", "pps", "ppsm", "ppsx", "odp",
    "otp", "fodp", "xls", "xlsb", "xlsx", "xlsm", "xlt", "xltm", "xltx", "ods", "ots", "dxf",
    "dwg",
];

/// XPS/OpenXPS go through the shared GhostXPS interpreter instead of
/// LibreOffice; they are page documents neither backend reads natively.
const GXPS_EXTENSIONS: [&str; 2] = ["xps", "oxps"];

fn needs_soffice(ext: &str) -> bool {
    SOFFICE_EXTENSIONS.contains(&ext)
}

fn needs_gxps(ext: &str) -> bool {
    GXPS_EXTENSIONS.contains(&ext)
}

/// Whether this viewer can render the extension at all, native or converted.
pub fn is_supported(ext: &str) -> bool {
    let ext = ext.to_ascii_lowercase();
    NATIVE_EXTENSIONS.contains(&ext.as_str()) || needs_soffice(&ext) || needs_gxps(&ext)
}

pub struct PreparedDocument {
    pub file_path: PathBuf,
    pub display_name: String,
    temp_dir: Option<PathBuf>,
}

impl PreparedDocument {
    fn direct(file_path: &Path) -> Self {
        Self {
            file_path: file_path.to_path_buf(),
            display_name: file_name(file_path),
            temp_dir: None,
        }
    }

    fn temporary(file_path: PathBuf, display_name: String, temp_dir: PathBuf) -> Self {
        Self {
            file_path,
            display_name,
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

fn file_name(path: &Path) -> String {
    path.file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.display().to_string())
}

fn normalized_extension(path: &Path) -> String {
    path.extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| ext.to_ascii_lowercase())
        .unwrap_or_default()
}

fn create_temp_directory(purpose: &str) -> io::Result<PathBuf> {
    let pid = std::process::id();
    let id = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
    let dir = std::env::temp_dir()
        .join("Inf-Dir")
        .join(VIEWER_DIR_NAME)
        .join(format!("{purpose}-{pid}-{id}"));
    fs::create_dir_all(&dir)?;
    Ok(dir)
}

fn push_unique(roots: &mut Vec<PathBuf>, root: PathBuf) {
    if !roots.contains(&root) {
        roots.push(root);
    }
}

/// Directories that may contain a runtime, ordered from the most specific (a
/// copy shipped inside this package) to the most general (a shared runtime
/// prepared in the source tree).
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

fn find_on_path(executable: &str) -> Option<PathBuf> {
    let path_var = std::env::var_os("PATH")?;
    std::env::split_paths(&path_var)
        .map(|dir| dir.join(executable))
        .find(|candidate| candidate.is_file())
}

/// Locate `<directory>\<executable>` under one of [`runtime_search_roots`].
fn find_runtime_tool(directory: &str, executable: &str) -> Option<PathBuf> {
    runtime_search_roots()
        .into_iter()
        .map(|root| root.join(directory).join(executable))
        .find(|candidate| candidate.is_file())
}

/// Resolve `soffice.exe`: an explicit override, then the shared runtime
/// package, then a machine-wide LibreOffice install, then PATH.
fn find_libreoffice() -> Option<PathBuf> {
    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Ok(configured) = std::env::var("INF_DIR_LIBREOFFICE_PATH") {
        candidates.push(PathBuf::from(configured));
    }
    for root in runtime_search_roots() {
        candidates.push(root.join("libreoffice").join("program").join("soffice.exe"));
    }
    for env_var in ["ProgramFiles", "ProgramFiles(x86)"] {
        if let Some(program_files) = std::env::var_os(env_var) {
            candidates.push(
                PathBuf::from(program_files)
                    .join("LibreOffice")
                    .join("program")
                    .join("soffice.exe"),
            );
        }
    }

    for candidate in candidates {
        if candidate.is_file() {
            return Some(candidate);
        }
        if candidate.is_dir() {
            let direct = candidate.join("soffice.exe");
            if direct.is_file() {
                return Some(direct);
            }
            let nested = candidate.join("program").join("soffice.exe");
            if nested.is_file() {
                return Some(nested);
            }
        }
    }

    find_on_path("soffice.exe").or_else(|| find_on_path("soffice.com"))
}

/// `gxpswin64.exe` from the shared GhostXPS runtime turns XPS/OpenXPS into PDF.
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

pub fn prepare_document(source: &Path) -> Result<PreparedDocument, String> {
    let ext = normalized_extension(source);
    if ext == "pdf" {
        return Ok(PreparedDocument::direct(source));
    }
    let display_name = file_name(source);
    if needs_gxps(&ext) {
        return convert_xps(source, display_name);
    }
    if needs_soffice(&ext) {
        return convert_to_pdf(source, display_name);
    }
    Err(format!("unsupported file type: .{ext}"))
}

/// `soffice.exe` stays resident while the converted document is written, but
/// it drives the real worker as a child process, so a timeout has to take the
/// whole tree down.
fn convert_to_pdf(source: &Path, display_name: String) -> Result<PreparedDocument, String> {
    let soffice = find_libreoffice().ok_or_else(|| {
        "该格式需要 LibreOffice 转换运行时。请运行 plugins\\build.bat 安装共享运行时包，或设置 INF_DIR_LIBREOFFICE_PATH。"
            .to_string()
    })?;

    let temp_dir = create_temp_directory("libreoffice")
        .map_err(|e| format!("无法创建 LibreOffice 转换临时目录: {e}"))?;
    let profile = temp_dir.join("profile");
    let output_dir = temp_dir.join("output");
    if let Err(e) = fs::create_dir_all(&profile).and_then(|_| fs::create_dir_all(&output_dir)) {
        let _ = fs::remove_dir_all(&temp_dir);
        return Err(format!("无法准备 LibreOffice 转换目录: {e}"));
    }

    // A private user profile keeps headless from reusing a running LibreOffice
    // instance, which would route the conversion to the wrong process.
    let profile_uri = file_uri(&profile);
    let args: Vec<String> = vec![
        "--headless".to_string(),
        "--nologo".to_string(),
        "--nodefault".to_string(),
        "--nofirststartwizard".to_string(),
        "--norestore".to_string(),
        "--nolockcheck".to_string(),
        format!("-env:UserInstallation={profile_uri}"),
        "--convert-to".to_string(),
        CONVERSION_FILTER.to_string(),
        "--outdir".to_string(),
        output_dir.to_string_lossy().into_owned(),
        source.to_string_lossy().into_owned(),
    ];

    let mut child = match Command::new(&soffice)
        .args(&args)
        .current_dir(&temp_dir)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .creation_flags(CREATE_NO_WINDOW)
        .spawn()
    {
        Ok(child) => child,
        Err(e) => {
            let _ = fs::remove_dir_all(&temp_dir);
            return Err(format!("无法启动 LibreOffice: {e}"));
        }
    };

    match wait_with_timeout(&mut child, CONVERT_TIMEOUT) {
        Ok(status) if status.success() => {}
        Ok(status) => {
            let (stdout, stderr) = capture(&mut child);
            let _ = fs::remove_dir_all(&temp_dir);
            let detail = first_non_empty(&stderr, &stdout)
                .unwrap_or_else(|| format!("LibreOffice 以退出码 {status} 结束"));
            return Err(format!("转换为 PDF 失败: {detail}"));
        }
        Err(e) => {
            let _ = fs::remove_dir_all(&temp_dir);
            return Err(format!("等待 LibreOffice 转换失败: {e}"));
        }
    }

    let stem = source.file_stem().unwrap_or_default();
    let converted = output_dir.join(Path::new(stem)).with_extension(CONVERSION_FILTER);
    if !converted.is_file() {
        let (stdout, stderr) = capture(&mut child);
        let _ = fs::remove_dir_all(&temp_dir);
        let detail =
            first_non_empty(&stderr, &stdout).unwrap_or_else(|| "没有生成输出文件".to_string());
        return Err(format!("转换为 PDF 失败: {detail}"));
    }

    Ok(PreparedDocument::temporary(converted, display_name, temp_dir))
}

/// XPS and OpenXPS are converted with the shared GhostXPS interpreter; the
/// resulting PDF keeps the vector content.
fn convert_xps(source: &Path, display_name: String) -> Result<PreparedDocument, String> {
    let gxps = find_gxps().ok_or_else(|| {
        "XPS 查看需要共享 GhostXPS 运行时。请运行 plugins\\build.bat 安装共享运行时包，或设置 INF_DIR_GXPS_PATH。"
            .to_string()
    })?;

    let temp_dir = create_temp_directory("xps")
        .map_err(|e| format!("Failed to create temporary directory for XPS: {e}"))?;
    let stem = source
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("document");
    let output_pdf = temp_dir.join(format!("{stem}.pdf"));

    let source_str = source.to_string_lossy();
    let output_arg = format!("-o{}", output_pdf.to_string_lossy());
    let result = Command::new(&gxps)
        .args([
            "-q",
            "-dNOPAUSE",
            "-dBATCH",
            "-sDEVICE=pdfwrite",
            output_arg.as_str(),
            source_str.as_ref(),
        ])
        .stdin(Stdio::null())
        .creation_flags(CREATE_NO_WINDOW)
        .output();

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

    Ok(PreparedDocument::temporary(output_pdf, display_name, temp_dir))
}

fn wait_with_timeout(child: &mut Child, timeout: Duration) -> io::Result<ExitStatus> {
    let deadline = Instant::now() + timeout;
    loop {
        match child.try_wait() {
            Ok(Some(status)) => return Ok(status),
            Ok(None) => {}
            Err(e) => return Err(e),
        }
        if Instant::now() >= deadline {
            kill_process_tree(child.id());
            let _ = child.kill();
            let _ = child.wait();
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                format!("LibreOffice 转换超过 {} 秒", timeout.as_secs()),
            ));
        }
        thread::sleep(POLL_INTERVAL);
    }
}

/// `taskkill /T` walks the live snapshot, so it still reaches the LibreOffice
/// worker after the launcher has gone.
fn kill_process_tree(pid: u32) {
    let _ = Command::new("taskkill")
        .args(["/F", "/T", "/PID", &pid.to_string()])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .creation_flags(CREATE_NO_WINDOW)
        .spawn();
}

fn capture(child: &mut Child) -> (String, String) {
    use std::io::Read;
    let read = |stream: Option<&mut dyn Read>| -> String {
        let mut buffer = Vec::new();
        if let Some(inner) = stream {
            let _ = inner.read_to_end(&mut buffer);
        }
        String::from_utf8_lossy(&buffer).into_owned()
    };
    let stdout = match child.stdout.as_mut() {
        Some(ref mut stream) => read(Some(stream as &mut dyn Read)),
        None => String::new(),
    };
    let stderr = match child.stderr.as_mut() {
        Some(ref mut stream) => read(Some(stream as &mut dyn Read)),
        None => String::new(),
    };
    (stdout, stderr)
}

fn first_non_empty(primary: &str, secondary: &str) -> Option<String> {
    let primary = primary.trim();
    if !primary.is_empty() {
        return Some(primary.to_string());
    }
    let secondary = secondary.trim();
    (!secondary.is_empty()).then(|| secondary.to_string())
}

/// Build a `file:` URI without pulling in a URI crate; LibreOffice only accepts
/// the directory form for `UserInstallation`.
fn file_uri(path: &Path) -> String {
    let raw = path.to_string_lossy().replace('\\', "/");
    let encoded: String = raw
        .chars()
        .map(|c| match c {
            '#' => "%23".to_string(),
            '?' => "%3f".to_string(),
            '%' => "%25".to_string(),
            other => other.to_string(),
        })
        .collect();
    let trailing = if encoded.ends_with('/') {
        String::new()
    } else {
        "/".to_string()
    };
    // A UNC path already carries its authority; a drive path does not, so the
    // empty authority is spelled out as the third slash.
    if let Some(unc) = encoded.strip_prefix("//") {
        format!("file://{unc}{trailing}")
    } else {
        format!("file:///{encoded}{trailing}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pdf_renders_without_conversion() {
        assert!(is_supported("pdf"));
        assert!(!needs_soffice("pdf"));
        assert!(!needs_gxps("pdf"));
    }

    #[test]
    fn office_cad_and_web_archive_formats_convert_via_soffice() {
        for ext in [
            "doc", "docx", "odt", "rtf", "wps", "ppt", "pptx", " odp", "xls", "xlsx", "ods",
            "mhtml", "dxf", "dwg",
        ] {
            assert!(needs_soffice(ext.trim()), "{ext} must convert");
            assert!(is_supported(ext.trim()), "{ext} must be supported");
        }
    }

    #[test]
    fn xps_formats_convert_via_ghostxps() {
        for ext in ["xps", "oxps"] {
            assert!(needs_gxps(ext), "{ext} must convert");
            assert!(is_supported(ext), "{ext} must be supported");
        }
    }

    #[test]
    fn unsupported_formats_are_rejected_before_conversion() {
        for ext in ["epub", "cbz", "vsd", "vsdx", "djvu", "zip", "txt", ""] {
            assert!(!is_supported(ext), "{ext} is out of scope");
        }
        assert!(prepare_document(Path::new("C:\\tmp\\book.epub")).is_err());
    }

    #[test]
    fn runtime_roots_start_at_the_executable_and_offer_the_shared_layouts() {
        let roots = runtime_search_roots();
        let exe_dir = std::env::current_exe().unwrap().parent().unwrap().to_path_buf();
        assert_eq!(roots.first(), Some(&exe_dir));
        assert!(roots.iter().any(|root| root.ends_with(SHARED_RUNTIME_PACKAGE)));
        assert!(roots.iter().any(|root| root.ends_with(SHARED_RUNTIME_DIR)));
        assert!(roots.iter().any(|root| root.ends_with(VIEWER_DIR_NAME)));
    }

    #[test]
    fn runtime_search_roots_are_unique() {
        let roots = runtime_search_roots();
        let unique: std::collections::HashSet<_> = roots.iter().collect();
        assert_eq!(roots.len(), unique.len());
    }

    #[test]
    fn profile_uri_is_absolute_and_directory_terminated() {
        let uri = file_uri(Path::new("C:\\Users\\me\\AppData\\Local\\Temp\\Inf-Dir\\profile"));
        assert_eq!(
            uri,
            "file:///C:/Users/me/AppData/Local/Temp/Inf-Dir/profile/"
        );
    }

    #[test]
    fn profile_uri_keeps_a_unc_authority() {
        let uri = file_uri(Path::new("\\\\share\\docs\\profile"));
        assert_eq!(uri, "file://share/docs/profile/");
    }
}
