//! Inf-Dir email Quick View host.
//!
//! The email itself is parsed out-of-process by `email-parse.exe` (a Native
//! AOT .NET tool wrapping MsgReader/MimeKit), which writes `report.json` and
//! `attachments/<id>` payload files into a private staging directory. This
//! shell serves that directory (plus the static web assets) through the
//! shared WebView2 shell and handles the save-attachment and open-link IPC.
//! The staging directory is removed when the window closes.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;

use http::{Request, StatusCode};
use serde_json::Value;
use viewer_web_shell::{mime_for, response, safe_join, WebViewConfig};
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};
use windows::core::{PCWSTR, PWSTR};
use windows::Win32::Foundation::{HINSTANCE, HWND, LPARAM};
use windows::Win32::UI::Controls::Dialogs::{
    GetSaveFileNameW, OFN_EXPLORER, OFN_HIDEREADONLY, OFN_OVERWRITEPROMPT, OFN_PATHMUSTEXIST,
    OPENFILENAMEW,
};

const SCHEME: &str = "http";
const HOST: &str = "email-view.local";
const SUPPORTED_EXTENSIONS: [&str; 5] = ["eml", "emlx", "msg", "oft", "dat"];

#[link(name = "shell32")]
extern "system" {
    fn ShellExecuteW(
        hwnd: *mut core::ffi::c_void,
        operation: *const u16,
        file: *const u16,
        parameters: *const u16,
        directory: *const u16,
        show_command: i32,
    ) -> isize;
}

struct Args {
    file: PathBuf,
    window_placement: Option<WindowPlacement>,
}

fn parse_args() -> Result<Args, String> {
    parse_args_from(std::env::args().skip(1))
}

fn parse_args_from(args: impl IntoIterator<Item = String>) -> Result<Args, String> {
    let mut file = None;
    let mut window_placement = None;
    let mut it = args.into_iter();

    while let Some(arg) = it.next() {
        match arg.as_str() {
            WINDOW_PLACEMENT_ARGUMENT => {
                if window_placement.is_some() {
                    return Err(format!("duplicate option: {WINDOW_PLACEMENT_ARGUMENT}"));
                }
                let value = it
                    .next()
                    .ok_or_else(|| format!("{WINDOW_PLACEMENT_ARGUMENT} requires a JSON value"))?;
                window_placement = Some(WindowPlacement::from_json(&value)?);
            }
            _ if arg.starts_with('-') && arg != "-" => {
                return Err(format!("unknown option: {arg}"));
            }
            _ => {
                if file.replace(PathBuf::from(arg)).is_some() {
                    return Err("unexpected second file argument".to_owned());
                }
            }
        }
    }

    let file = file.ok_or_else(|| {
        format!(
            "usage: email-view.exe <EMAIL_FILE> [{WINDOW_PLACEMENT_ARGUMENT} <JSON>], extensions: {}",
            SUPPORTED_EXTENSIONS.join(", ")
        )
    })?;
    if !file.is_file() {
        return Err(format!("file does not exist: {}", file.display()));
    }
    if !is_supported_extension(&file) {
        return Err(format!("unsupported email extension: {}", file.display()));
    }

    Ok(Args {
        file,
        window_placement,
    })
}

fn is_supported_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|value| value.to_str())
        .is_some_and(|extension| {
            SUPPORTED_EXTENSIONS
                .iter()
                .any(|candidate| candidate.eq_ignore_ascii_case(extension))
        })
}

/// Shared immutable state for request and IPC handlers.
struct Shell {
    assets_root: PathBuf,
    staging: PathBuf,
    report: Value,
}

/// Runs the out-of-process parser; any failure is surfaced as an error
/// report instead of blocking the window (mirrors the C# ParseSafely).
fn run_parser(exe_dir: &Path, source: &Path, staging: &Path) -> Result<(), String> {
    let parser = exe_dir.join("email-parse.exe");
    if !parser.is_file() {
        return Err(format!("email parser not found: {}", parser.display()));
    }
    let output = Command::new(&parser)
        .arg(source)
        .arg("--out")
        .arg(staging)
        .output()
        .map_err(|error| format!("cannot start email parser: {error}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let detail = stderr.trim();
        return Err(if detail.is_empty() {
            format!("email parser exited with status {}", output.status)
        } else {
            format!("email parser failed: {detail}")
        });
    }
    Ok(())
}

fn load_report(staging: &Path, fallback_error: Option<String>, source: &Path) -> Value {
    if let Ok(bytes) = fs::read(staging.join("report.json")) {
        if let Ok(Value::Object(map)) = serde_json::from_slice::<Value>(&bytes) {
            return Value::Object(map);
        }
    }
    let message = fallback_error.unwrap_or_else(|| "无法解析邮件：解析结果缺失。".to_owned());
    serde_json::json!({
        "sourceFileName": source
            .file_name()
            .map(|value| value.to_string_lossy().into_owned())
            .unwrap_or_default(),
        "sourcePath": source.display().to_string(),
        "subject": "",
        "attachments": [],
        "error": message,
    })
}

fn attachment_by_id<'a>(report: &'a Value, id: &str) -> Option<&'a Value> {
    report["attachments"]
        .as_array()?
        .iter()
        .find(|attachment| attachment["id"].as_str() == Some(id))
}

fn handle_request(req: Request<Vec<u8>>, shell: &Shell) -> viewer_web_shell::WebResponse {
    let path = if req.uri().path().is_empty() || req.uri().path() == "/" {
        "/index.html"
    } else {
        req.uri().path()
    };

    if path == "/report.json" || path == "/save-state.json" {
        return match fs::read(shell.staging.join(path.trim_start_matches('/'))) {
            Ok(bytes) => response(StatusCode::OK, "application/json; charset=utf-8", bytes),
            Err(_) => response(
                StatusCode::NOT_FOUND,
                "application/json; charset=utf-8",
                b"{\"error\":\"not available\"}".to_vec(),
            ),
        };
    }

    if let Some(raw_id) = path.strip_prefix("/inline/") {
        let id = percent_encoding::percent_decode_str(raw_id)
            .decode_utf8_lossy()
            .into_owned();
        let inline = attachment_by_id(&shell.report, &id)
            .is_some_and(|attachment| attachment["inline"].as_bool() == Some(true));
        if !inline {
            return response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                b"inline attachment not found".to_vec(),
            );
        }
        let content_type = attachment_by_id(&shell.report, &id)
            .and_then(|attachment| attachment["contentType"].as_str())
            .unwrap_or("application/octet-stream")
            .to_owned();
        return match fs::read(shell.staging.join("attachments").join(&id)) {
            Ok(bytes) => response(StatusCode::OK, &content_type, bytes),
            Err(_) => response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                b"attachment data missing".to_vec(),
            ),
        };
    }

    match safe_join(&shell.assets_root, path) {
        Some(target) => match fs::read(&target) {
            Ok(bytes) => response(StatusCode::OK, mime_for(&target), bytes),
            Err(_) => response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                format!("resource not found: {path}").into_bytes(),
            ),
        },
        None => response(
            StatusCode::BAD_REQUEST,
            "text/plain; charset=utf-8",
            b"bad request".to_vec(),
        ),
    }
}

fn handle_ipc(req: Request<String>, shell: &Shell) {
    let Ok(message) = serde_json::from_str::<Value>(req.body()) else {
        return;
    };
    match message["type"].as_str() {
        Some("saveAttachment") => save_attachment(message["id"].as_str(), shell),
        Some("openLink") => open_external_link(message["url"].as_str().unwrap_or_default()),
        _ => {}
    }
}

fn save_attachment(id: Option<&str>, shell: &Shell) {
    let Some(id) = id.filter(|value| !value.is_empty()) else {
        return;
    };
    let Some(attachment) = attachment_by_id(&shell.report, id) else {
        return;
    };
    let data = match fs::read(shell.staging.join("attachments").join(id)) {
        Ok(bytes) => bytes,
        Err(_) => return,
    };

    let default_name = attachment["name"].as_str().unwrap_or("attachment.bin");
    let Some(destination) = save_file_dialog(default_name) else {
        return;
    };
    if fs::write(&destination, &data).is_err() {
        return;
    }

    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|value| value.as_millis())
        .unwrap_or_default();
    let state = serde_json::json!({ "id": id, "stamp": stamp });
    let _ = fs::write(
        shell.staging.join("save-state.json"),
        state.to_string().as_bytes(),
    );
}

fn save_file_dialog(default_name: &str) -> Option<PathBuf> {
    let mut buffer = vec![0u16; 4096];
    let source: Vec<u16> = default_name
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect();
    let copy_len = source.len().min(buffer.len() - 1);
    buffer[..copy_len].copy_from_slice(&source[..copy_len]);

    let title: Vec<u16> = "保存附件"
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect();
    let filter: Vec<u16> = "所有文件 (*.*)\0*.*\0\0"
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect();

    let mut options = OPENFILENAMEW {
        lStructSize: std::mem::size_of::<OPENFILENAMEW>() as u32,
        hwndOwner: HWND::default(),
        hInstance: HINSTANCE::default(),
        lpstrFilter: PCWSTR(filter.as_ptr()),
        lpstrCustomFilter: PWSTR::null(),
        nMaxCustFilter: 0,
        nFilterIndex: 0,
        lpstrFile: PWSTR(buffer.as_mut_ptr()),
        nMaxFile: buffer.len() as u32,
        lpstrFileTitle: PWSTR::null(),
        nMaxFileTitle: 0,
        lpstrInitialDir: PCWSTR::null(),
        lpstrTitle: PCWSTR(title.as_ptr()),
        Flags: OFN_HIDEREADONLY | OFN_PATHMUSTEXIST | OFN_OVERWRITEPROMPT | OFN_EXPLORER,
        nFileOffset: 0,
        nFileExtension: 0,
        lpstrDefExt: PCWSTR::null(),
        lCustData: LPARAM::default(),
        lpfnHook: None,
        lpTemplateName: PCWSTR::null(),
        pvReserved: std::ptr::null_mut(),
        dwReserved: 0,
        FlagsEx: windows::Win32::UI::Controls::Dialogs::OPEN_FILENAME_FLAGS_EX::default(),
    };

    let ok = unsafe { GetSaveFileNameW(&mut options) };
    if !ok.as_bool() {
        return None;
    }
    let end = buffer
        .iter()
        .position(|value| *value == 0)
        .unwrap_or(buffer.len());
    Some(PathBuf::from(String::from_utf16_lossy(&buffer[..end])))
}

fn open_external_link(url: &str) {
    if url.is_empty()
        || url.len() > 4096
        || !(url.starts_with("https://")
            || url.starts_with("http://")
            || url.starts_with("mailto:"))
    {
        return;
    }
    let operation = wide("open");
    let target = wide(url);
    unsafe {
        ShellExecuteW(
            std::ptr::null_mut(),
            operation.as_ptr(),
            target.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            1,
        );
    }
}

fn wide(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(std::iter::once(0)).collect()
}

fn main() {
    let args = match parse_args() {
        Ok(args) => args,
        Err(error) => {
            eprintln!("[email-view] {error}");
            std::process::exit(1);
        }
    };
    let source = match args.file.canonicalize() {
        Ok(path) => path,
        Err(error) => {
            eprintln!("[email-view] failed to resolve file: {error}");
            std::process::exit(1);
        }
    };
    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|path| path.parent().map(|value| value.to_path_buf()))
        .unwrap_or_else(|| PathBuf::from("."));

    let temp_root = std::env::temp_dir().join("Inf-Dir").join("email-view");
    let staging = temp_root.join(format!(
        "{}-{:?}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|value| value.subsec_nanos())
            .unwrap_or_default()
    ));
    if let Err(error) = fs::create_dir_all(&staging) {
        eprintln!("[email-view] cannot create staging directory: {error}");
        std::process::exit(1);
    }

    let parser_failure = run_parser(&exe_dir, &source, &staging).err();
    let report = load_report(&staging, parser_failure, &source);

    let title_base = report_value_or(&report, "subject")
        .or_else(|| report_value_or(&report, "sourceFileName"))
        .unwrap_or_else(|| "Email".to_owned());
    let shell = Arc::new(Shell {
        assets_root: exe_dir.join("email-view-web"),
        staging: staging.clone(),
        report,
    });

    let request_shell = Arc::clone(&shell);
    let router = Arc::new(move |request| handle_request(request, &request_shell));
    let ipc_shell = Arc::clone(&shell);
    let ipc = Arc::new(move |message: Request<String>| handle_ipc(message, &ipc_shell));

    let config = WebViewConfig {
        title: format!("{title_base} - Email View"),
        host: HOST.to_owned(),
        scheme: SCHEME.to_owned(),
        start_url: format!("{SCHEME}://{HOST}/index.html"),
        window_placement: args.window_placement,
        request_handler: router,
        ipc_handler: Some(ipc),
    };
    let result = viewer_web_shell::run(config);
    let _ = fs::remove_dir_all(&staging);
    if let Err(error) = result {
        eprintln!("[email-view] {error}");
        std::process::exit(1);
    }
}

fn report_value_or(report: &Value, key: &str) -> Option<String> {
    report[key]
        .as_str()
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mail_fixture(extension: &str) -> PathBuf {
        static COUNTER: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let path = std::env::temp_dir().join(format!(
            "inf-dir-email-view-arg-test-{}-{}.{}",
            std::process::id(),
            COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed),
            extension
        ));
        fs::write(&path, b"dummy").unwrap();
        path
    }

    #[test]
    fn parses_window_placement_before_or_after_file() {
        let fixture = mail_fixture("msg");
        let placement_json = r#"{"version":2,"x":1024,"y":0,"clientWidth":1008,"clientHeight":1113,"maximized":false}"#;
        for arguments in [
            vec![
                fixture.to_string_lossy().into_owned(),
                WINDOW_PLACEMENT_ARGUMENT.to_owned(),
                placement_json.to_owned(),
            ],
            vec![
                WINDOW_PLACEMENT_ARGUMENT.to_owned(),
                placement_json.to_owned(),
                fixture.to_string_lossy().into_owned(),
            ],
        ] {
            let args = parse_args_from(arguments).unwrap();
            assert_eq!(args.window_placement.unwrap().x, 1024);
        }
        fs::remove_file(&fixture).unwrap();
    }

    #[test]
    fn rejects_unknown_options_and_unsupported_extensions() {
        assert!(parse_args_from(vec!["--unknown".to_owned()]).is_err());
        let fixture = mail_fixture("eml");
        assert!(parse_args_from(vec![
            fixture.to_string_lossy().into_owned(),
            fixture.to_string_lossy().into_owned(),
        ])
        .is_err());
        fs::remove_file(&fixture).unwrap();
        let exe = mail_fixture("exe");
        assert!(parse_args_from(vec![exe.to_string_lossy().into_owned()]).is_err());
        fs::remove_file(&exe).unwrap();
    }

    #[test]
    fn missing_report_gets_fallback_error() {
        let directory = std::env::temp_dir().join(format!(
            "inf-dir-email-view-report-test-{}",
            std::process::id()
        ));
        fs::create_dir_all(&directory).unwrap();
        let report = load_report(
            &directory,
            Some("email parser failed".to_owned()),
            Path::new("C:/sample.chinese.msg"),
        );
        assert_eq!(report["error"], "email parser failed");
        assert_eq!(report["sourceFileName"], "sample.chinese.msg");
        assert!(report["attachments"].is_array());

        fs::write(
            directory.join("report.json"),
            r#"{"subject":"繁体","attachments":[{"id":"0","name":"a.png","contentType":"image/png","inline":true}]}"#,
        )
        .unwrap();
        let report = load_report(&directory, None, Path::new("C:/sample.msg"));
        assert_eq!(report["subject"], "繁体");
        assert!(attachment_by_id(&report, "0").is_some());
        assert!(attachment_by_id(&report, "404").is_none());
        let _ = fs::remove_dir_all(&directory);
    }

    #[test]
    fn inline_route_requires_inline_attachment() {
        let directory = std::env::temp_dir().join(format!(
            "inf-dir-email-view-inline-test-{}",
            std::process::id()
        ));
        let assets = directory.join("assets");
        fs::create_dir_all(&assets).unwrap();
        fs::create_dir_all(directory.join("attachments")).unwrap();
        fs::write(directory.join("attachments/0"), b"png-bytes").unwrap();
        let report: Value = serde_json::from_str(
            r#"{"attachments":[{"id":"0","name":"a.png","contentType":"image/png","inline":true},
                               {"id":"1","name":"doc.bin","contentType":"application/octet-stream","inline":false}]}"#,
        )
        .unwrap();
        let shell = Shell {
            assets_root: assets.clone(),
            staging: directory.clone(),
            report,
        };

        let request = Request::builder()
            .uri("/inline/0")
            .body(Vec::new())
            .unwrap();
        let response = handle_request(request, &shell);
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(response.headers().get("content-type").unwrap(), "image/png");

        let request = Request::builder()
            .uri("/inline/1")
            .body(Vec::new())
            .unwrap();
        assert_eq!(
            handle_request(request, &shell).status(),
            StatusCode::NOT_FOUND
        );

        fs::write(assets.join("index.html"), b"<html>ok</html>").unwrap();
        let request = Request::builder()
            .uri("/index.html")
            .body(Vec::new())
            .unwrap();
        assert_eq!(handle_request(request, &shell).status(), StatusCode::OK);

        let request = Request::builder()
            .uri("/../secret")
            .body(Vec::new())
            .unwrap();
        assert_eq!(
            handle_request(request, &shell).status(),
            StatusCode::BAD_REQUEST
        );

        let _ = fs::remove_dir_all(&directory);
    }
}
