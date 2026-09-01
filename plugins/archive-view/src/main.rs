use std::collections::HashMap;
use std::ffi::{c_char, c_int, c_void, CStr};
use std::fs::{self, File};
use std::io::Write;
use std::os::windows::ffi::OsStrExt;
use std::path::{Component, Path};
use std::process::ExitCode;
use std::sync::Arc;
use std::time::{Duration, SystemTime};

use eframe::egui;
use egui_ltreeview::{NodeBuilder, TreeView, TreeViewState};
use viewer_window_placement::{WindowPlacement, ARGUMENT};

extern "C" {
    fn archive_read_new() -> *mut c_void;
    fn archive_read_support_filter_all(a: *mut c_void) -> c_int;
    fn archive_read_support_format_all(a: *mut c_void) -> c_int;
    fn archive_read_open_filename_w(a: *mut c_void, path: *const u16, block_size: usize) -> c_int;
    fn archive_read_next_header(a: *mut c_void, entry: *mut *mut c_void) -> c_int;
    fn archive_read_data(a: *mut c_void, buff: *mut c_void, size: usize) -> isize;
    fn archive_read_data_skip(a: *mut c_void) -> c_int;
    fn archive_read_free(a: *mut c_void) -> c_int;
    fn archive_error_string(a: *mut c_void) -> *const c_char;
    fn archive_entry_pathname_w(entry: *mut c_void) -> *const u16;
    fn archive_entry_size(entry: *mut c_void) -> i64;
    fn archive_entry_mode(entry: *mut c_void) -> u32;
    fn archive_entry_mtime(entry: *mut c_void) -> i64;
    fn archive_entry_filetype(entry: *mut c_void) -> u32;
}

const ARCHIVE_OK: c_int = 0;
const ARCHIVE_EOF: c_int = 1;
const AE_IFDIR: u32 = 0o040000;
const MAX_COMIC_BYTES: u64 = 512 * 1024 * 1024;
const MAX_COMIC_PAGES: usize = 10_000;

struct ArchiveEntry {
    pathname: String,
    size: i64,
    mode: u32,
    mtime: Option<SystemTime>,
    is_dir: bool,
}

fn sevenzip_executable() -> Result<std::path::PathBuf, String> {
    let path = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|dir| dir.join("7z.exe")))
        .ok_or_else(|| "archive-view executable has no parent directory".to_owned())?;
    if !path.is_file() {
        return Err(format!("bundled 7z.exe not found: {}", path.display()));
    }
    Ok(path)
}

fn days_from_civil(y: i64, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = if m > 2 { m - 3 } else { m + 9 } as i64;
    let doy = (153 * mp + 2) / 5 + d as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

fn parse_sevenzip_timestamp(raw: &str) -> Option<SystemTime> {
    let raw = raw.trim();
    let timestamp = raw.split('.').next()?.trim();
    let mut parts = timestamp.split_whitespace();
    let date = parts.next()?;
    let time = parts.next().unwrap_or("00:00:00");
    let mut date_parts = date.split('-');
    let y: i64 = date_parts.next()?.parse().ok()?;
    let m: u32 = date_parts.next()?.parse().ok()?;
    let d: u32 = date_parts.next()?.parse().ok()?;
    let mut time_parts = time.split(':');
    let h: i64 = time_parts.next().unwrap_or("0").parse().unwrap_or(0);
    let min: i64 = time_parts.next().unwrap_or("0").parse().unwrap_or(0);
    let s: i64 = time_parts.next().unwrap_or("0").parse().unwrap_or(0);
    let secs = days_from_civil(y, m, d) * 86_400 + h * 3_600 + min * 60 + s;
    SystemTime::UNIX_EPOCH.checked_add(Duration::from_secs(secs as u64))
}

fn parse_sevenzip_mode(mode: &str, is_dir: bool) -> u32 {
    let mode = mode.trim();
    if mode.len() == 10 && mode.starts_with(['d', '-']) {
        let mut value = 0u32;
        let permission_bytes = mode.as_bytes();
        for (shift, triple) in permission_bytes[1..].chunks(3).enumerate() {
            let mut bits = 0u32;
            if !triple.is_empty() && triple[0] == b'r' {
                bits |= 0o4;
            }
            if triple.len() > 1 && triple[1] == b'w' {
                bits |= 0o2;
            }
            if triple.len() > 2 && (triple[2] == b'x' || triple[2] == b't' || triple[2] == b's') {
                bits |= 0o1;
            }
            value |= bits << (6 - 3 * shift);
        }
        return value | if is_dir { AE_IFDIR } else { 0 };
    }
    if is_dir {
        AE_IFDIR
    } else {
        0
    }
}

fn parse_sevenzip_listing(output: &str) -> Vec<ArchiveEntry> {
    let mut entries = Vec::new();
    let normalized = output.replace("\r\n", "\n");
    for block in normalized.split("\n\n") {
        let mut pathname: Option<String> = None;
        let mut size: i64 = 0;
        let mut mode: u32 = 0;
        let mut mtime: Option<SystemTime> = None;
        let mut is_dir = false;
        let mut has_path = false;

        for line in block.lines() {
            let Some((key, value)) = line.split_once(" = ") else {
                continue;
            };
            let value = value.trim();
            match key.trim() {
                "Path" => {
                    has_path = true;
                    pathname = Some(value.to_string());
                }
                "Folder" => is_dir = value == "+",
                "Attributes" => is_dir = is_dir || value.starts_with('D'),
                "Size" => size = value.parse().unwrap_or(0),
                "Mode" => mode = parse_sevenzip_mode(value, is_dir),
                "Modified" => mtime = parse_sevenzip_timestamp(value),
                _ => {}
            }
        }

        if !has_path {
            continue;
        }
        if let Some(path) = pathname {
            if path.is_empty() {
                continue;
            }
            entries.push(ArchiveEntry {
                pathname: path,
                size,
                mode,
                mtime,
                is_dir,
            });
        }
    }

    entries.sort_by_key(|entry| entry.pathname.to_lowercase());
    entries
}

fn read_archive_sevenzip(path: &str) -> Result<Vec<ArchiveEntry>, String> {
    let executable = sevenzip_executable()?;
    let output = std::process::Command::new(&executable)
        .arg("l")
        .arg("-slt")
        .arg("-ba")
        .arg("-sccUTF-8")
        .arg("--")
        .arg(path)
        .output()
        .map_err(|error| format!("failed to start {}: {error}", executable.display()))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!(
            "7z exited with {}: {}",
            output.status.code().unwrap_or(-1),
            stderr.trim()
        ));
    }

    let text = String::from_utf8_lossy(&output.stdout).into_owned();
    let entries = parse_sevenzip_listing(&text);
    if entries.is_empty() {
        return Err("7z listed no entries".into());
    }
    Ok(entries)
}

fn read_archive(path: &str) -> Result<Vec<ArchiveEntry>, String> {
    unsafe {
        let a = archive_read_new();
        if a.is_null() {
            return Err("failed to allocate archive reader".into());
        }

        archive_read_support_filter_all(a);
        archive_read_support_format_all(a);

        let w_path: Vec<u16> = std::ffi::OsStr::new(path)
            .encode_wide()
            .chain([0])
            .collect();
        if archive_read_open_filename_w(a, w_path.as_ptr(), 10240) != ARCHIVE_OK {
            let msg = error_msg(a);
            archive_read_free(a);
            return Err(format!("failed to open archive: {msg}"));
        }

        let mut entries = Vec::new();
        let mut entry: *mut c_void = std::ptr::null_mut();

        loop {
            let r = archive_read_next_header(a, &mut entry);
            if r == ARCHIVE_EOF {
                break;
            }
            if r != ARCHIVE_OK {
                let msg = error_msg(a);
                archive_read_free(a);
                return Err(format!("failed reading archive entry: {msg}"));
            }

            let pathname = {
                let p = archive_entry_pathname_w(entry);
                if p.is_null() {
                    String::new()
                } else {
                    let mut len = 0;
                    while *p.add(len) != 0 {
                        len += 1;
                    }
                    String::from_utf16_lossy(std::slice::from_raw_parts(p, len))
                }
            };

            let mtime_secs = archive_entry_mtime(entry);
            let mtime = if mtime_secs > 0 {
                SystemTime::UNIX_EPOCH.checked_add(Duration::from_secs(mtime_secs as u64))
            } else {
                None
            };

            entries.push(ArchiveEntry {
                pathname,
                size: archive_entry_size(entry),
                mode: archive_entry_mode(entry),
                mtime,
                is_dir: archive_entry_filetype(entry) == AE_IFDIR,
            });
        }

        archive_read_free(a);

        entries.sort_by_key(|entry| entry.pathname.to_lowercase());
        Ok(entries)
    }
}

unsafe fn error_msg(a: *mut c_void) -> String {
    let p = archive_error_string(a);
    if p.is_null() {
        "unknown error".into()
    } else {
        CStr::from_ptr(p).to_string_lossy().into_owned()
    }
}

fn is_comic_image(path: &Path) -> bool {
    matches!(
        path.extension()
            .and_then(|extension| extension.to_str())
            .map(|extension| extension.to_ascii_lowercase())
            .as_deref(),
        Some("jpg")
            | Some("jpeg")
            | Some("jfif")
            | Some("png")
            | Some("gif")
            | Some("bmp")
            | Some("webp")
            | Some("tif")
            | Some("tiff")
            | Some("avif")
            | Some("jxl")
            | Some("jp2")
            | Some("j2k")
    )
}

fn safe_archive_path(raw: &str) -> Option<std::path::PathBuf> {
    let normalized = raw.replace('\\', "/");
    let mut relative = std::path::PathBuf::new();
    for component in Path::new(&normalized).components() {
        match component {
            Component::Normal(value) => {
                if value.to_string_lossy().contains(':') {
                    return None;
                }
                relative.push(value);
            }
            Component::CurDir => {}
            Component::Prefix(_) | Component::RootDir | Component::ParentDir => return None,
        }
    }
    (!relative.as_os_str().is_empty()).then_some(relative)
}

fn extract_comic(path: &str, output_directory: &str) -> Result<(), String> {
    fs::create_dir_all(output_directory)
        .map_err(|error| format!("failed to create extraction directory: {error}"))?;

    let archive = unsafe { archive_read_new() };
    if archive.is_null() {
        return Err("failed to allocate archive reader".into());
    }

    let result = (|| unsafe {
        archive_read_support_filter_all(archive);
        archive_read_support_format_all(archive);

        let wide_path: Vec<u16> = std::ffi::OsStr::new(path)
            .encode_wide()
            .chain([0])
            .collect();
        if archive_read_open_filename_w(archive, wide_path.as_ptr(), 10240) != ARCHIVE_OK {
            return Err(format!("failed to open archive: {}", error_msg(archive)));
        }

        let mut entry: *mut c_void = std::ptr::null_mut();
        let mut page_count = 0usize;
        let mut total_bytes = 0u64;
        loop {
            let status = archive_read_next_header(archive, &mut entry);
            if status == ARCHIVE_EOF {
                break;
            }
            if status != ARCHIVE_OK {
                return Err(format!("failed reading archive: {}", error_msg(archive)));
            }

            let raw_name = {
                let name = archive_entry_pathname_w(entry);
                if name.is_null() {
                    String::new()
                } else {
                    let mut length = 0;
                    while *name.add(length) != 0 {
                        length += 1;
                    }
                    String::from_utf16_lossy(std::slice::from_raw_parts(name, length))
                }
            };
            let Some(relative) = safe_archive_path(&raw_name) else {
                archive_read_data_skip(archive);
                continue;
            };
            if archive_entry_filetype(entry) == AE_IFDIR || !is_comic_image(&relative) {
                archive_read_data_skip(archive);
                continue;
            }
            page_count += 1;
            if page_count > MAX_COMIC_PAGES {
                return Err("CBR archive contains too many comic pages".into());
            }

            let target = Path::new(output_directory).join(relative);
            if let Some(parent) = target.parent() {
                fs::create_dir_all(parent)
                    .map_err(|error| format!("failed to create page directory: {error}"))?;
            }
            let mut output = File::create(&target)
                .map_err(|error| format!("failed to create extracted page: {error}"))?;
            let mut buffer = [0u8; 64 * 1024];
            loop {
                let size =
                    archive_read_data(archive, buffer.as_mut_ptr().cast::<c_void>(), buffer.len());
                if size == 0 {
                    break;
                }
                if size < 0 {
                    return Err(format!("failed reading comic page: {}", error_msg(archive)));
                }
                total_bytes = total_bytes
                    .checked_add(size as u64)
                    .ok_or_else(|| "CBR image data size overflowed".to_owned())?;
                if total_bytes > MAX_COMIC_BYTES {
                    return Err("CBR image data exceeds the 512 MiB preview limit".into());
                }
                output
                    .write_all(&buffer[..size as usize])
                    .map_err(|error| format!("failed writing extracted page: {error}"))?;
            }
        }

        if page_count == 0 {
            return Err("CBR archive contains no supported comic images".into());
        }
        Ok(())
    })();

    unsafe { archive_read_free(archive) };
    result
}

fn human_size(bytes: i64) -> String {
    if bytes <= 0 {
        return "0 B".to_string();
    }
    const UNITS: [&str; 6] = ["B", "KB", "MB", "GB", "TB", "PB"];
    let mut v = bytes as f64;
    let mut i = 0;
    while v >= 1024.0 && i < UNITS.len() - 1 {
        v /= 1024.0;
        i += 1;
    }
    if i == 0 {
        format!("{bytes} B")
    } else {
        format!("{:.1} {}", v, UNITS[i])
    }
}

fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    (y, m as u32, d as u32)
}

fn format_mtime(t: Option<SystemTime>) -> String {
    let Some(t) = t else {
        return String::new();
    };
    let Ok(dur) = t.duration_since(SystemTime::UNIX_EPOCH) else {
        return String::new();
    };
    let secs = dur.as_secs() as i64;
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    let (y, m, d) = civil_from_days(days);
    format!(
        "{y:04}-{m:02}-{d:02} {:02}:{:02}:{:02}",
        rem / 3600,
        (rem % 3600) / 60,
        rem % 60
    )
}

fn mode_string(mode: u32, is_dir: bool) -> String {
    let t = if is_dir { 'd' } else { '-' };
    format!("{t}{:03o}", mode & 0o777)
}

struct TreeNode {
    name: String,
    parent: Option<usize>,
    children: Vec<usize>,
    files: Vec<usize>,
    entry_index: Option<usize>,
}

fn build_tree(entries: &[ArchiveEntry]) -> Vec<TreeNode> {
    let mut nodes: Vec<TreeNode> = vec![TreeNode {
        name: "/".to_string(),
        parent: None,
        children: Vec::new(),
        files: Vec::new(),
        entry_index: None,
    }];
    let mut dir_map: HashMap<String, usize> = HashMap::new();
    dir_map.insert(String::new(), 0);

    for (idx, entry) in entries.iter().enumerate() {
        let parts: Vec<&str> = entry
            .pathname
            .split(['/', '\\'])
            .filter(|part| !part.is_empty())
            .collect();
        if parts.is_empty() {
            continue;
        }

        let mut parent = 0usize;
        let mut current_path = String::new();
        let directory_parts = if entry.is_dir {
            parts.len()
        } else {
            parts.len() - 1
        };

        for (depth, part) in parts.iter().take(directory_parts).enumerate() {
            if current_path.is_empty() {
                current_path = part.to_string();
            } else {
                current_path = format!("{current_path}/{part}");
            }

            if let Some(&existing) = dir_map.get(&current_path) {
                parent = existing;
                if entry.is_dir && depth == directory_parts - 1 {
                    nodes[existing].entry_index = Some(idx);
                }
            } else {
                let is_explicit_dir = entry.is_dir && depth == directory_parts - 1;
                let node_idx = nodes.len();
                nodes.push(TreeNode {
                    name: part.to_string(),
                    parent: Some(parent),
                    children: Vec::new(),
                    files: Vec::new(),
                    entry_index: is_explicit_dir.then_some(idx),
                });
                nodes[parent].children.push(node_idx);
                dir_map.insert(current_path.clone(), node_idx);
                parent = node_idx;
            }
        }

        if !entry.is_dir {
            nodes[parent].files.push(idx);
        }
    }

    nodes
}

fn entry_name(pathname: &str) -> &str {
    pathname
        .trim_end_matches(['/', '\\'])
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or(pathname)
}

#[derive(Clone, Copy)]
enum DirItem {
    Directory(usize),
    File(usize),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum FileIconKind {
    Folder,
    Image,
    Video,
    Audio,
    Pdf,
    Archive,
    Document,
    Spreadsheet,
    Presentation,
    Code,
    Text,
    Font,
    Executable,
    Generic,
}

fn file_icon_kind(name: &str) -> FileIconKind {
    let extension = name
        .rsplit_once('.')
        .filter(|(stem, _)| !stem.is_empty())
        .map(|(_, extension)| extension.to_ascii_lowercase());

    match extension.as_deref().unwrap_or_default() {
        "jpg" | "jpeg" | "png" | "gif" | "bmp" | "webp" | "svg" | "ico" | "tif" | "tiff"
        | "heic" | "avif" | "raw" | "psd" => FileIconKind::Image,
        "mp4" | "mkv" | "avi" | "mov" | "wmv" | "webm" | "m4v" | "flv" | "mpg" | "mpeg" | "3gp" => {
            FileIconKind::Video
        }
        "mp3" | "wav" | "flac" | "aac" | "ogg" | "m4a" | "wma" | "opus" | "mid" | "midi" => {
            FileIconKind::Audio
        }
        "pdf" => FileIconKind::Pdf,
        "zip" | "7z" | "rar" | "tar" | "gz" | "gzip" | "bz2" | "xz" | "zst" | "cab" | "iso"
        | "tgz" | "tbz2" | "txz" => FileIconKind::Archive,
        "doc" | "docx" | "odt" | "rtf" | "pages" => FileIconKind::Document,
        "xls" | "xlsx" | "csv" | "ods" | "numbers" => FileIconKind::Spreadsheet,
        "ppt" | "pptx" | "odp" | "key" => FileIconKind::Presentation,
        "rs" | "dart" | "py" | "js" | "jsx" | "ts" | "tsx" | "java" | "kt" | "kts" | "c" | "cc"
        | "cpp" | "h" | "hpp" | "cs" | "go" | "php" | "rb" | "swift" | "sh" | "ps1" | "bat"
        | "cmd" | "html" | "htm" | "css" | "scss" | "sass" | "less" | "vue" | "svelte" | "sql"
        | "yaml" | "yml" | "toml" | "json" | "xml" => FileIconKind::Code,
        "txt" | "md" | "log" | "ini" | "cfg" | "conf" | "nfo" => FileIconKind::Text,
        "ttf" | "otf" | "woff" | "woff2" => FileIconKind::Font,
        "exe" | "msi" | "dll" | "sys" | "com" | "appx" => FileIconKind::Executable,
        _ => FileIconKind::Generic,
    }
}

fn paint_file_icon(painter: &egui::Painter, rect: egui::Rect, kind: FileIconKind) {
    let icon = egui::Rect::from_center_size(rect.center(), egui::vec2(16.0, 16.0));

    if kind == FileIconKind::Folder {
        let tab = egui::Rect::from_min_max(
            icon.min + egui::vec2(1.0, 2.5),
            icon.min + egui::vec2(7.5, 6.0),
        );
        let body = egui::Rect::from_min_max(
            icon.min + egui::vec2(1.0, 5.0),
            icon.max - egui::vec2(1.0, 1.5),
        );
        painter.rect_filled(tab, 1.5, egui::Color32::from_rgb(239, 181, 64));
        painter.rect_filled(body, 2.0, egui::Color32::from_rgb(224, 156, 35));
        painter.line_segment(
            [body.left_top(), body.right_top()],
            egui::Stroke::new(1.0, egui::Color32::from_rgb(190, 124, 24)),
        );
        return;
    }

    let color = match kind {
        FileIconKind::Image => egui::Color32::from_rgb(53, 145, 96),
        FileIconKind::Video => egui::Color32::from_rgb(130, 88, 183),
        FileIconKind::Audio => egui::Color32::from_rgb(190, 75, 143),
        FileIconKind::Pdf => egui::Color32::from_rgb(207, 67, 61),
        FileIconKind::Archive => egui::Color32::from_rgb(126, 105, 75),
        FileIconKind::Document => egui::Color32::from_rgb(53, 112, 190),
        FileIconKind::Spreadsheet => egui::Color32::from_rgb(42, 132, 84),
        FileIconKind::Presentation => egui::Color32::from_rgb(205, 98, 49),
        FileIconKind::Code => egui::Color32::from_rgb(49, 120, 140),
        FileIconKind::Text => egui::Color32::from_rgb(102, 116, 132),
        FileIconKind::Font => egui::Color32::from_rgb(89, 91, 168),
        FileIconKind::Executable => egui::Color32::from_rgb(83, 94, 108),
        FileIconKind::Generic => egui::Color32::from_rgb(126, 140, 155),
        FileIconKind::Folder => unreachable!(),
    };
    let min = icon.min + egui::vec2(2.0, 1.0);
    let max = icon.max - egui::vec2(2.0, 1.0);
    let fold = 4.0;
    painter.add(egui::Shape::convex_polygon(
        vec![
            min,
            egui::pos2(max.x - fold, min.y),
            egui::pos2(max.x, min.y + fold),
            max,
            egui::pos2(min.x, max.y),
        ],
        color,
        egui::Stroke::new(0.8, egui::Color32::from_black_alpha(65)),
    ));
    painter.add(egui::Shape::convex_polygon(
        vec![
            egui::pos2(max.x - fold, min.y),
            egui::pos2(max.x - fold, min.y + fold),
            egui::pos2(max.x, min.y + fold),
        ],
        egui::Color32::from_white_alpha(105),
        egui::Stroke::NONE,
    ));

    let white = egui::Color32::from_white_alpha(235);
    let stroke = egui::Stroke::new(1.1, white);
    match kind {
        FileIconKind::Image => {
            painter.circle_filled(icon.min + egui::vec2(6.0, 6.0), 1.2, white);
            painter.line_segment(
                [
                    icon.min + egui::vec2(4.0, 12.0),
                    icon.min + egui::vec2(7.0, 8.5),
                ],
                stroke,
            );
            painter.line_segment(
                [
                    icon.min + egui::vec2(7.0, 8.5),
                    icon.min + egui::vec2(11.5, 12.0),
                ],
                stroke,
            );
        }
        FileIconKind::Video => {
            painter.add(egui::Shape::convex_polygon(
                vec![
                    icon.min + egui::vec2(6.0, 5.0),
                    icon.min + egui::vec2(11.5, 8.0),
                    icon.min + egui::vec2(6.0, 11.0),
                ],
                white,
                egui::Stroke::NONE,
            ));
        }
        FileIconKind::Audio => {
            painter.line_segment(
                [
                    icon.min + egui::vec2(9.5, 4.5),
                    icon.min + egui::vec2(9.5, 10.5),
                ],
                stroke,
            );
            painter.line_segment(
                [
                    icon.min + egui::vec2(9.5, 4.5),
                    icon.min + egui::vec2(12.0, 4.0),
                ],
                stroke,
            );
            painter.circle_filled(icon.min + egui::vec2(7.5, 11.0), 1.8, white);
        }
        FileIconKind::Archive => {
            for y in [5.0, 7.5, 10.0] {
                painter.rect_filled(
                    egui::Rect::from_center_size(
                        icon.min + egui::vec2(8.0, y),
                        egui::vec2(2.2, 1.5),
                    ),
                    0.2,
                    white,
                );
            }
        }
        FileIconKind::Document | FileIconKind::Text => {
            for y in [6.0, 8.5, 11.0] {
                painter.line_segment(
                    [
                        icon.min + egui::vec2(5.0, y),
                        icon.min + egui::vec2(11.0, y),
                    ],
                    stroke,
                );
            }
        }
        FileIconKind::Spreadsheet => {
            for x in [6.5, 9.5] {
                painter.line_segment(
                    [
                        icon.min + egui::vec2(x, 5.0),
                        icon.min + egui::vec2(x, 12.0),
                    ],
                    egui::Stroke::new(0.8, white),
                );
            }
            for y in [7.3, 9.7] {
                painter.line_segment(
                    [
                        icon.min + egui::vec2(4.5, y),
                        icon.min + egui::vec2(11.5, y),
                    ],
                    egui::Stroke::new(0.8, white),
                );
            }
        }
        FileIconKind::Presentation => {
            painter.rect_stroke(
                egui::Rect::from_min_max(
                    icon.min + egui::vec2(4.5, 5.0),
                    icon.min + egui::vec2(11.5, 10.0),
                ),
                0.5,
                egui::Stroke::new(0.9, white),
                egui::StrokeKind::Inside,
            );
            painter.line_segment(
                [
                    icon.min + egui::vec2(8.0, 10.0),
                    icon.min + egui::vec2(8.0, 12.0),
                ],
                stroke,
            );
        }
        FileIconKind::Pdf | FileIconKind::Code | FileIconKind::Font | FileIconKind::Executable => {
            let mark = match kind {
                FileIconKind::Pdf => "PDF",
                FileIconKind::Code => "<>",
                FileIconKind::Font => "A",
                FileIconKind::Executable => "EX",
                _ => unreachable!(),
            };
            painter.text(
                icon.center() + egui::vec2(0.0, 2.0),
                egui::Align2::CENTER_CENTER,
                mark,
                egui::FontId::proportional(if kind == FileIconKind::Pdf { 5.3 } else { 7.0 }),
                white,
            );
        }
        FileIconKind::Generic | FileIconKind::Folder => {}
    }
}

fn folder_icon(ui: &mut egui::Ui) {
    let (rect, _) = ui.allocate_exact_size(egui::vec2(16.0, 16.0), egui::Sense::hover());
    paint_file_icon(ui.painter(), rect, FileIconKind::Folder);
}

struct ArchiveApp {
    path: String,
    entries: Vec<ArchiveEntry>,
    nodes: Vec<TreeNode>,
    selected_dir: usize,
    pending_tree_selection: Option<usize>,
    col_widths: [f32; 4],
    tree_width: f32,
    drag_origin_widths: [f32; 4],
}

impl ArchiveApp {
    fn select_dir(&mut self, node_idx: usize) {
        if node_idx < self.nodes.len() {
            self.selected_dir = node_idx;
            self.pending_tree_selection = Some(node_idx);
        }
    }

    fn select_parent(&mut self) -> bool {
        let Some(parent_idx) = self.nodes[self.selected_dir].parent else {
            return false;
        };
        self.select_dir(parent_idx);
        true
    }

    fn dir_contents(&self, node_idx: usize) -> Vec<DirItem> {
        let node = &self.nodes[node_idx];
        node.children
            .iter()
            .copied()
            .map(DirItem::Directory)
            .chain(node.files.iter().copied().map(DirItem::File))
            .collect()
    }
}

impl eframe::App for ArchiveApp {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        let ctx = ui.ctx().clone();
        if ctx.input(|i| i.key_pressed(egui::Key::Escape)) {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }

        egui::Panel::top("header")
            .frame(
                egui::Frame::NONE
                    .fill(egui::Color32::from_rgb(38, 50, 66))
                    .inner_margin(egui::Margin::symmetric(12, 7)),
            )
            .show(ui, |ui| {
                ui.horizontal_centered(|ui| {
                    let can_go_up = self.nodes[self.selected_dir].parent.is_some();
                    let arrow_color = if can_go_up {
                        egui::Color32::WHITE
                    } else {
                        egui::Color32::from_rgb(105, 119, 136)
                    };
                    let up_button =
                        egui::Button::new(egui::RichText::new("↑").color(arrow_color).size(18.0))
                            .min_size(egui::vec2(30.0, 26.0))
                            .fill(egui::Color32::from_rgb(49, 65, 84))
                            .stroke(egui::Stroke::new(1.0, egui::Color32::from_rgb(79, 96, 116)));
                    let up_response = ui
                        .add_enabled(can_go_up, up_button)
                        .on_hover_text("Up one level");
                    if up_response.clicked() {
                        self.select_parent();
                    }
                    ui.add_space(4.0);
                    ui.heading(
                        egui::RichText::new(&self.path)
                            .color(egui::Color32::WHITE)
                            .strong(),
                    );
                    ui.add_space(16.0);
                    ui.label(
                        egui::RichText::new(format!("{} entries", self.entries.len()))
                            .color(egui::Color32::from_rgb(158, 178, 200)),
                    );
                });
            });

        let table_bg = egui::Color32::from_rgb(247, 249, 252);
        let tree_bg = egui::Color32::from_rgb(240, 244, 248);
        let text_color = egui::Color32::from_rgb(38, 50, 66);
        let text_secondary = egui::Color32::from_rgb(110, 122, 138);
        let hover_bg = egui::Color32::from_rgb(227, 237, 250);
        let header_bg = egui::Color32::from_rgb(232, 238, 244);
        let divider_color = egui::Color32::from_rgb(213, 221, 230);
        let accent = egui::Color32::from_rgb(21, 101, 192);

        egui::CentralPanel::default()
            .frame(egui::Frame::NONE.fill(table_bg))
            .show(ui, |ui| {
                let available = ui.available_size();

                let splitter_w = 5.0;
                let tree_max = (available.x - splitter_w - 120.0).max(80.0);
                let tree_w = self.tree_width.clamp(80.0, tree_max);
                let table_w = (available.x - tree_w - splitter_w).max(0.0);

                ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = 0.0;

                    let (tree_rect, _) = ui
                        .allocate_exact_size(egui::vec2(tree_w, available.y), egui::Sense::hover());
                    ui.scope_builder(
                        egui::UiBuilder::new()
                            .id_salt("tree_panel")
                            .max_rect(tree_rect)
                            .layout(egui::Layout::top_down(egui::Align::Min)),
                        |ui| {
                            ui.painter().rect_filled(tree_rect, 0.0, tree_bg);
                            ui.painter().vline(
                                tree_rect.max.x,
                                tree_rect.y_range(),
                                egui::Stroke::new(1.0, divider_color),
                            );
                            egui::ScrollArea::both()
                                .id_salt("tree_scroll")
                                .auto_shrink([false, false])
                                .show(ui, |ui| {
                                    let id = ui.make_persistent_id("archive_tree");
                                    let mut state =
                                        TreeViewState::<usize>::load(ui, id).unwrap_or_default();
                                    if let Some(node_idx) = self.pending_tree_selection.take() {
                                        state.set_one_selected(node_idx);
                                        let mut ancestor = Some(node_idx);
                                        while let Some(idx) = ancestor {
                                            state.set_openness(idx, true);
                                            ancestor = self.nodes[idx].parent;
                                        }
                                        state.store(ui, id);
                                    } else if state.selected().is_empty() {
                                        state.set_one_selected(0);
                                        state.set_openness(0, true);
                                        state.store(ui, id);
                                    }
                                    let (_response, actions) =
                                        TreeView::new(id).show(ui, |builder| {
                                            self.build_tree_node(builder, 0);
                                        });
                                    for action in actions {
                                        if let egui_ltreeview::Action::SetSelected(ids) = action {
                                            if let Some(&node_idx) = ids.first() {
                                                if node_idx < self.nodes.len() {
                                                    self.selected_dir = node_idx;
                                                }
                                            }
                                        }
                                    }
                                });
                        },
                    );

                    let splitter = ui.allocate_exact_size(
                        egui::vec2(splitter_w, available.y),
                        egui::Sense::drag(),
                    );
                    let sr = splitter.1.rect;
                    let is_active = splitter.1.dragged() || splitter.1.hovered();
                    ui.painter().rect_filled(
                        sr,
                        0.0,
                        if is_active { accent } else { divider_color },
                    );
                    if is_active {
                        ctx.output_mut(|o| {
                            o.cursor_icon = egui::CursorIcon::ResizeColumn;
                        });
                    }
                    if splitter.1.dragged() {
                        self.tree_width =
                            (self.tree_width + splitter.1.drag_delta().x).clamp(80.0, tree_max);
                    }

                    let (table_rect, _) = ui.allocate_exact_size(
                        egui::vec2(table_w, available.y),
                        egui::Sense::hover(),
                    );
                    ui.scope_builder(
                        egui::UiBuilder::new()
                            .id_salt("table_panel")
                            .max_rect(table_rect)
                            .layout(egui::Layout::top_down(egui::Align::Min)),
                        |ui| {
                            let row_height = ui.spacing().interact_size.y + 4.0;
                            let contents = self.dir_contents(self.selected_dir);
                            let headers = ["Name", "Size", "Modified", "Mode"];

                            // Column x positions shared by the header and the rows.
                            let mut cumulative_x = [0.0f32; 4];
                            cumulative_x[0] = table_rect.min.x;
                            for i in 1..4 {
                                cumulative_x[i] = cumulative_x[i - 1] + self.col_widths[i - 1];
                            }

                            let (hdr_rect, _) = ui.allocate_exact_size(
                                egui::vec2(table_w, row_height),
                                egui::Sense::hover(),
                            );
                            ui.painter().rect_filled(hdr_rect, 0.0, header_bg);
                            let header_font = egui::TextStyle::Body.resolve(ui.style());
                            for (i, header) in headers.iter().enumerate() {
                                ui.painter().text(
                                    egui::pos2(cumulative_x[i] + 8.0, hdr_rect.center().y),
                                    egui::Align2::LEFT_CENTER,
                                    *header,
                                    header_font.clone(),
                                    text_secondary,
                                );
                            }

                            // Column dividers with drag handles.
                            for (i, &column_x) in cumulative_x.iter().take(3).enumerate() {
                                let boundary = column_x + self.col_widths[i];
                                let handle_rect = egui::Rect::from_min_size(
                                    egui::pos2(boundary - 3.0, hdr_rect.min.y),
                                    egui::vec2(6.0, row_height),
                                );
                                let resp = ui.interact(
                                    handle_rect,
                                    ui.make_persistent_id(("col_handle", i)),
                                    egui::Sense::drag(),
                                );
                                if resp.hovered() || resp.dragged() {
                                    ctx.output_mut(|o| {
                                        o.cursor_icon = egui::CursorIcon::ResizeColumn;
                                    });
                                }
                                if resp.drag_started() {
                                    self.drag_origin_widths = self.col_widths;
                                }
                                if let Some(total) = resp.total_drag_delta() {
                                    let dx = total.x;
                                    self.col_widths[i] =
                                        (self.drag_origin_widths[i] + dx).max(40.0);
                                    self.col_widths[i + 1] =
                                        (self.drag_origin_widths[i + 1] - dx).max(40.0);
                                }
                                ui.painter().vline(
                                    boundary,
                                    hdr_rect.y_range(),
                                    egui::Stroke::new(1.0, divider_color),
                                );
                            }

                            ui.painter().hline(
                                hdr_rect.x_range(),
                                hdr_rect.max.y,
                                egui::Stroke::new(1.0, divider_color),
                            );

                            egui::ScrollArea::vertical()
                                .id_salt("table_scroll")
                                .auto_shrink([false, false])
                                .show(ui, |ui| {
                                    for item in &contents {
                                        let (
                                            row_id,
                                            name,
                                            size,
                                            mtime,
                                            mode,
                                            icon_kind,
                                            target_dir,
                                        ) = match *item {
                                            DirItem::Directory(node_idx) => {
                                                let node = &self.nodes[node_idx];
                                                let entry = node
                                                    .entry_index
                                                    .map(|entry_idx| &self.entries[entry_idx]);
                                                (
                                                    ui.make_persistent_id(("dir_row", node_idx)),
                                                    node.name.clone(),
                                                    String::new(),
                                                    entry.and_then(|entry| entry.mtime),
                                                    entry
                                                        .map(|entry| {
                                                            mode_string(entry.mode, entry.is_dir)
                                                        })
                                                        .unwrap_or_default(),
                                                    FileIconKind::Folder,
                                                    Some(node_idx),
                                                )
                                            }
                                            DirItem::File(entry_idx) => {
                                                let entry = &self.entries[entry_idx];
                                                let name = entry_name(&entry.pathname).to_string();
                                                (
                                                    ui.make_persistent_id(("file_row", entry_idx)),
                                                    name.clone(),
                                                    human_size(entry.size),
                                                    entry.mtime,
                                                    mode_string(entry.mode, false),
                                                    file_icon_kind(&name),
                                                    None,
                                                )
                                            }
                                        };

                                        let row_rect = ui.allocate_space(egui::vec2(
                                            ui.available_width(),
                                            row_height,
                                        ));
                                        let row_rect = row_rect.1;

                                        let response =
                                            ui.interact(row_rect, row_id, egui::Sense::click());
                                        if response.hovered() {
                                            ui.painter().rect_filled(row_rect, 0.0, hover_bg);
                                        }
                                        if response.double_clicked() {
                                            if let Some(node_idx) = target_dir {
                                                self.select_dir(node_idx);
                                            }
                                        }

                                        let modified = format_mtime(mtime);
                                        let cols = [&name, &size, &modified, &mode];
                                        for (i, text) in cols.iter().enumerate() {
                                            let w = self.col_widths[i];
                                            let cell_rect = egui::Rect::from_min_size(
                                                egui::pos2(cumulative_x[i], row_rect.min.y),
                                                egui::vec2(w, row_height),
                                            );
                                            if i == 0 {
                                                let icon_rect = egui::Rect::from_center_size(
                                                    egui::pos2(
                                                        cell_rect.min.x + 14.0,
                                                        cell_rect.center().y,
                                                    ),
                                                    egui::vec2(18.0, 18.0),
                                                );
                                                paint_file_icon(ui.painter(), icon_rect, icon_kind);
                                            }
                                            ui.painter().with_clip_rect(cell_rect).text(
                                                egui::pos2(
                                                    cell_rect.min.x
                                                        + if i == 0 { 27.0 } else { 4.0 },
                                                    cell_rect.center().y,
                                                ),
                                                egui::Align2::LEFT_CENTER,
                                                *text,
                                                egui::FontId::monospace(13.0),
                                                text_color,
                                            );
                                        }
                                    }
                                });
                        },
                    );
                });
            });
    }
}

impl ArchiveApp {
    fn build_tree_node(&self, builder: &mut egui_ltreeview::TreeViewBuilder<usize>, idx: usize) {
        let node = &self.nodes[idx];
        if node.children.is_empty() {
            builder.node(
                NodeBuilder::leaf(idx)
                    .icon(folder_icon)
                    .label(node.name.clone()),
            );
        } else {
            builder.node(
                NodeBuilder::dir(idx)
                    .default_open(idx == 0)
                    .icon(folder_icon)
                    .label(node.name.clone()),
            );
            for &child in &node.children {
                self.build_tree_node(builder, child);
            }
            builder.close_dir();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(pathname: &str, is_dir: bool) -> ArchiveEntry {
        ArchiveEntry {
            pathname: pathname.to_string(),
            size: if is_dir { 0 } else { 128 },
            mode: if is_dir { AE_IFDIR } else { 0 },
            mtime: None,
            is_dir,
        }
    }

    fn child_named(nodes: &[TreeNode], parent: usize, name: &str) -> usize {
        nodes[parent]
            .children
            .iter()
            .copied()
            .find(|&idx| nodes[idx].name == name)
            .unwrap_or_else(|| panic!("missing directory {name}"))
    }

    #[test]
    fn tree_contains_root_and_directories_only() {
        let entries = vec![
            entry("root.txt", false),
            entry("docs/", true),
            entry("docs/readme.md", false),
            entry("docs/images/logo.png", false),
            entry("empty/", true),
        ];

        let nodes = build_tree(&entries);
        let docs = child_named(&nodes, 0, "docs");
        let images = child_named(&nodes, docs, "images");
        let empty = child_named(&nodes, 0, "empty");

        assert_eq!(nodes.len(), 4);
        assert_eq!(nodes[0].name, "/");
        assert_eq!(nodes[0].parent, None);
        assert_eq!(nodes[0].files, vec![0]);
        assert_eq!(nodes[docs].parent, Some(0));
        assert_eq!(nodes[docs].entry_index, Some(1));
        assert_eq!(nodes[docs].files, vec![2]);
        assert_eq!(nodes[images].parent, Some(docs));
        assert_eq!(nodes[images].files, vec![3]);
        assert_eq!(nodes[empty].parent, Some(0));
        assert!(nodes[empty].children.is_empty());
        assert!(nodes[empty].files.is_empty());
    }

    #[test]
    fn tree_synthesizes_implicit_directories_and_windows_separators() {
        let entries = vec![entry("src\\nested\\main.rs", false)];

        let nodes = build_tree(&entries);
        let src = child_named(&nodes, 0, "src");
        let nested = child_named(&nodes, src, "nested");

        assert_eq!(nodes[nested].files, vec![0]);
        assert_eq!(entry_name(&entries[0].pathname), "main.rs");
    }

    #[test]
    fn parent_navigation_stops_at_root_and_syncs_tree_selection() {
        let entries = vec![entry("docs/readme.md", false)];
        let nodes = build_tree(&entries);
        let docs = child_named(&nodes, 0, "docs");
        let mut app = ArchiveApp {
            path: String::new(),
            entries,
            nodes,
            selected_dir: 0,
            pending_tree_selection: None,
            col_widths: [0.0; 4],
            tree_width: 0.0,
            drag_origin_widths: [0.0; 4],
        };

        app.select_dir(docs);
        assert_eq!(app.selected_dir, docs);
        assert_eq!(app.pending_tree_selection, Some(docs));
        assert!(app.select_parent());
        assert_eq!(app.selected_dir, 0);
        assert_eq!(app.pending_tree_selection, Some(0));
        assert!(!app.select_parent());
        assert_eq!(app.selected_dir, 0);
    }

    #[test]
    fn file_icons_are_selected_case_insensitively() {
        assert_eq!(file_icon_kind("photo.PNG"), FileIconKind::Image);
        assert_eq!(file_icon_kind("report.PDF"), FileIconKind::Pdf);
        assert_eq!(file_icon_kind("backup.tar.gz"), FileIconKind::Archive);
        assert_eq!(file_icon_kind("README"), FileIconKind::Generic);
    }

    #[test]
    fn cli_parses_window_placement() {
        let args = [
            "archive-view",
            "items.zip",
            ARGUMENT,
            r#"{"version":2,"x":-800,"y":20,"clientWidth":784,"clientHeight":861,"maximized":true}"#,
        ]
        .map(str::to_owned);

        let (path, placement) = parse_args(&args).unwrap();
        assert_eq!(path, "items.zip");
        assert_eq!(placement.unwrap().x, -800);
    }

    #[test]
    fn cli_rejects_missing_window_placement_json() {
        let args = ["archive-view", "items.zip", ARGUMENT].map(str::to_owned);
        let error = parse_args(&args).unwrap_err();
        assert_eq!(error, format!("missing JSON value after {ARGUMENT}"));
    }

    #[test]
    fn sevenzip_listing_parses_windows_style_entries() {
        let listing = "Path = file\r\nFolder = -\r\nSize = 2\r\n\
Modified = 2013-09-17 04:50:08.4607281\r\nAttributes = A\r\n\r\n\
Path = docs\r\nFolder = +\r\nSize = \r\nAttributes = D\r\n\r\n";

        let entries = parse_sevenzip_listing(listing);

        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].pathname, "docs");
        assert!(entries[0].is_dir);
        assert_eq!(entries[1].pathname, "file");
        assert_eq!(entries[1].size, 2);
        assert!(!entries[1].is_dir);
        assert_eq!(format_mtime(entries[1].mtime), "2013-09-17 04:50:08");
    }

    #[test]
    fn sevenzip_listing_parses_posix_mode_entries() {
        let listing = "Path = hid-inspector\\.journal\nFolder = -\nSize = 524288\n\
Mode = ----------\nModified = 2026-06-23 21:55:57\n\n\
Path = hid-inspector\nFolder = +\nMode = drwxr-xr-x\nModified = 2026-06-23 21:55:57\n";

        let entries = parse_sevenzip_listing(listing);

        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].pathname, "hid-inspector");
        assert_eq!(entries[0].mode, AE_IFDIR | 0o755);
        assert!(entries[0].is_dir);
        assert_eq!(format_mtime(entries[0].mtime), "2026-06-23 21:55:57");
        assert_eq!(entries[1].pathname, "hid-inspector\\.journal");
        assert_eq!(entries[1].mode, 0);
    }

    #[test]
    fn sevenzip_listing_skips_blocks_without_path() {
        let listing = "Type = Dmg\nPhysical Size = 325225\n\nPath = file\nFolder = -\nSize = 2\n";

        let entries = parse_sevenzip_listing(listing);

        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].pathname, "file");
    }

    #[test]
    fn sevenzip_mode_and_timestamp_parsing() {
        assert_eq!(parse_sevenzip_mode("drwxr-xr-x", true), AE_IFDIR | 0o755);
        assert_eq!(parse_sevenzip_mode("-rw-r--r--", false), 0o644);
        assert_eq!(parse_sevenzip_mode("", false), 0);
        assert_eq!(parse_sevenzip_mode("", true), AE_IFDIR);

        let t = parse_sevenzip_timestamp("2013-09-17 04:50:08.4607281").unwrap();
        assert_eq!(format_mtime(Some(t)), "2013-09-17 04:50:08");
        assert!(parse_sevenzip_timestamp("garbage").is_none());
        // Round-trip with the existing civil-from-days decoder.
        let t = parse_sevenzip_timestamp("1970-01-02 00:00:00").unwrap();
        assert_eq!(
            t.duration_since(SystemTime::UNIX_EPOCH).unwrap().as_secs(),
            86_400
        );
    }
}

fn parse_args(args: &[String]) -> Result<(String, Option<WindowPlacement>), String> {
    let mut file_arg = None;
    let mut placement = None;
    let mut i = 1;

    while i < args.len() {
        match args[i].as_str() {
            ARGUMENT => {
                if placement.is_some() {
                    return Err(format!("{ARGUMENT} may only be specified once"));
                }
                let value = args
                    .get(i + 1)
                    .ok_or_else(|| format!("missing JSON value after {ARGUMENT}"))?;
                placement = Some(
                    WindowPlacement::from_json(value)
                        .map_err(|error| format!("{ARGUMENT}: {error}"))?,
                );
                i += 2;
            }
            option if option.starts_with('-') => {
                return Err(format!("unknown option: {option}"));
            }
            value => {
                if file_arg.replace(value.to_owned()).is_some() {
                    return Err(format!("unexpected positional argument: {value}"));
                }
                i += 1;
            }
        }
    }

    let path = file_arg.ok_or_else(|| "missing archive file path".to_owned())?;
    Ok((path, placement))
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("--extract-comic") {
        if args.len() != 4 {
            eprintln!("Usage: archive-view --extract-comic <CBR_FILE> <OUTPUT_DIRECTORY>");
            return ExitCode::from(1);
        }
        if !Path::new(&args[2]).exists() {
            eprintln!("error: file not found: {}", args[2]);
            return ExitCode::from(1);
        }
        return match extract_comic(&args[2], &args[3]) {
            Ok(()) => ExitCode::SUCCESS,
            Err(error) => {
                eprintln!("error: {error}");
                ExitCode::from(1)
            }
        };
    }

    let (path, window_placement) = match parse_args(&args) {
        Ok(parsed) => parsed,
        Err(error) => {
            eprintln!("error: {error}");
            eprintln!("Usage: archive-view <FILE> [{ARGUMENT} <JSON>]");
            return ExitCode::from(1);
        }
    };

    if !Path::new(&path).exists() {
        eprintln!("error: file not found: {path}");
        return ExitCode::from(1);
    }

    let entries = match read_archive(&path).or_else(|libarchive_error| {
        read_archive_sevenzip(&path).map_err(|sevenzip_error| {
            format!("{libarchive_error}; 7-Zip fallback failed: {sevenzip_error}")
        })
    }) {
        Ok(e) => e,
        Err(err) => {
            eprintln!("error: {err}");
            return ExitCode::from(1);
        }
    };

    let nodes = build_tree(&entries);
    let selected_dir = 0;

    let title = format!("archive-view — {path}");
    let app = ArchiveApp {
        path: path.clone(),
        entries,
        nodes,
        selected_dir,
        pending_tree_selection: None,
        col_widths: [300.0, 100.0, 100.0, 100.0],
        tree_width: 280.0,
        drag_origin_widths: [0.0; 4],
    };

    let mut viewport = egui::ViewportBuilder::default().with_title(&title);
    viewport = match window_placement {
        Some(placement) => viewport
            .with_position([placement.x as f32, placement.y as f32])
            .with_inner_size([
                placement.client_width as f32,
                placement.client_height as f32,
            ])
            .with_maximized(placement.maximized),
        None => viewport.with_inner_size([1000.0, 680.0]),
    };

    let options = eframe::NativeOptions {
        viewport,
        ..Default::default()
    };

    if let Err(err) = eframe::run_native(
        "archive-view",
        options,
        Box::new(move |cc| {
            let mut fonts = egui::FontDefinitions::default();
            let font_path = "C:\\Windows\\Fonts\\msyh.ttc";
            if let Ok(data) = std::fs::read(font_path) {
                fonts.font_data.insert(
                    "msyh".to_owned(),
                    Arc::new(egui::FontData::from_owned(data)),
                );
                fonts
                    .families
                    .entry(egui::FontFamily::Proportional)
                    .or_default()
                    .insert(0, "msyh".to_owned());
                fonts
                    .families
                    .entry(egui::FontFamily::Monospace)
                    .or_default()
                    .push("msyh".to_owned());
            }
            cc.egui_ctx.set_fonts(fonts);
            // Always-visible scroll bars (default floating style is hard to spot).
            cc.egui_ctx.style_mut_of(egui::Theme::Light, |style| {
                style.spacing.scroll = egui::style::ScrollStyle::solid();
            });
            cc.egui_ctx.style_mut_of(egui::Theme::Dark, |style| {
                style.spacing.scroll = egui::style::ScrollStyle::solid();
            });
            Ok(Box::new(app) as Box<dyn eframe::App>)
        }),
    ) {
        eprintln!("error: failed to launch GUI: {err}");
        return ExitCode::from(1);
    }

    ExitCode::SUCCESS
}
