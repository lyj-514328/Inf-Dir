//! Inf-Dir CHM Quick View host.
//!
//! The CHMate JavaScript reader is served as static WebView2 content. The
//! custom protocol exposes the single CHM path supplied on the command line;
//! it does not accept arbitrary file paths from the page.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use http::{Request, StatusCode};
use percent_encoding::{percent_encode, NON_ALPHANUMERIC};
use serde::Deserialize;
use viewer_web_shell::{mime_for, response, safe_join, WebViewConfig};
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};

const SCHEME: &str = "http";
const HOST: &str = "chm-view.local";
const WEB_DIR_NAME: &str = "chm-view-web";
const SW_SHOWNORMAL: i32 = 1;

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
enum IpcMessage {
    Open { path: String },
    OpenUrl { url: String },
}

#[link(name = "shell32")]
extern "system" {
    fn ShellExecuteW(
        hwnd: *mut core::ffi::c_void,
        lp_operation: *const u16,
        lp_file: *const u16,
        lp_parameters: *const u16,
        lp_directory: *const u16,
        n_show_cmd: i32,
    ) -> isize;
}

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

fn shell_open(target: &str) {
    let operation = wide("open");
    let file = wide(target);
    unsafe {
        ShellExecuteW(
            std::ptr::null_mut(),
            operation.as_ptr(),
            file.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            SW_SHOWNORMAL,
        );
    }
}

fn handle_ipc(req: Request<String>) {
    match serde_json::from_str::<IpcMessage>(req.body()) {
        Ok(IpcMessage::Open { path }) => shell_open(&path),
        Ok(IpcMessage::OpenUrl { url })
            if url.starts_with("https://")
                || url.starts_with("http://")
                || url.starts_with("mailto:") =>
        {
            shell_open(&url);
        }
        Ok(IpcMessage::OpenUrl { url }) => {
            eprintln!("[chm-view] blocked external URL: {url}");
        }
        Err(error) => {
            eprintln!("[chm-view] invalid IPC message: {error}: {}", req.body());
        }
    }
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
        format!("usage: chm-view.exe <file.chm> [{WINDOW_PLACEMENT_ARGUMENT} <JSON>]")
    })?;
    if !file.is_file() {
        return Err(format!("file does not exist: {}", file.display()));
    }
    if !file
        .extension()
        .is_some_and(|extension| extension.eq_ignore_ascii_case("chm"))
    {
        return Err(format!("not a CHM file: {}", file.display()));
    }

    Ok(Args {
        file,
        window_placement,
    })
}

fn resolve_web_root() -> Option<PathBuf> {
    let mut candidates = Vec::new();
    if let Ok(executable) = std::env::current_exe() {
        let mut directory = executable.parent();
        for _ in 0..4 {
            let Some(current) = directory else { break };
            candidates.push(current.join(WEB_DIR_NAME));
            directory = current.parent();
        }
    }
    candidates.push(PathBuf::from(WEB_DIR_NAME));
    candidates
        .into_iter()
        .find(|directory| directory.join("index.html").is_file())
}

fn handle_request(
    req: Request<Vec<u8>>,
    web_root: &Path,
    source_file: &Path,
) -> viewer_web_shell::WebResponse {
    let path = req.uri().path();
    if path == "/file" {
        return match std::fs::read(source_file) {
            Ok(bytes) => response(StatusCode::OK, "application/octet-stream", bytes),
            Err(error) => response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                format!("failed to read CHM file: {error}").into_bytes(),
            ),
        };
    }

    let relative = if path.is_empty() || path == "/" {
        "index.html"
    } else {
        path
    };
    match safe_join(web_root, relative) {
        Some(target) => match std::fs::read(&target) {
            Ok(bytes) => response(StatusCode::OK, mime_for(&target), bytes),
            Err(_) => response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                format!("resource not found: {relative}").into_bytes(),
            ),
        },
        None => response(
            StatusCode::BAD_REQUEST,
            "text/plain; charset=utf-8",
            b"bad request".to_vec(),
        ),
    }
}

fn main() {
    let args = match parse_args() {
        Ok(args) => args,
        Err(error) => {
            eprintln!("[chm-view] {error}");
            std::process::exit(1);
        }
    };
    let web_root = match resolve_web_root() {
        Some(root) => root,
        None => {
            eprintln!("[chm-view] missing {WEB_DIR_NAME}/ beside the executable");
            std::process::exit(1);
        }
    };
    let source_file = match args.file.canonicalize() {
        Ok(path) => path,
        Err(error) => {
            eprintln!("[chm-view] failed to resolve file: {error}");
            std::process::exit(1);
        }
    };
    let name = source_file
        .file_name()
        .map(|value| value.to_string_lossy().into_owned())
        .unwrap_or_else(|| source_file.display().to_string());
    let file_url = "/file";
    let file_query = percent_encode(file_url.as_bytes(), NON_ALPHANUMERIC);
    let name_query = percent_encode(name.as_bytes(), NON_ALPHANUMERIC);
    let root = web_root.clone();
    let source = source_file.clone();
    let router = Arc::new(move |request| handle_request(request, &root, &source));
    let ipc = Arc::new(handle_ipc);
    let config = WebViewConfig {
        title: format!("{name} - CHM Viewer"),
        host: HOST.to_owned(),
        scheme: SCHEME.to_owned(),
        start_url: format!("{SCHEME}://{HOST}/index.html?file={file_query}&name={name_query}"),
        window_placement: args.window_placement,
        request_handler: router,
        ipc_handler: Some(ipc),
    };
    if let Err(error) = viewer_web_shell::run(config) {
        eprintln!("[chm-view] {error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn manifest_path() -> String {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("Cargo.toml")
            .to_string_lossy()
            .into_owned()
    }

    fn placement_json() -> String {
        r#"{"version":2,"x":1024,"y":0,"clientWidth":1008,"clientHeight":1113,"maximized":false}"#
            .to_owned()
    }

    #[test]
    fn parses_window_placement_before_or_after_file() {
        let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixture.chm");
        std::fs::write(&fixture, b"test").unwrap();
        for arguments in [
            vec![
                fixture.to_string_lossy().into_owned(),
                WINDOW_PLACEMENT_ARGUMENT.to_owned(),
                placement_json(),
            ],
            vec![
                WINDOW_PLACEMENT_ARGUMENT.to_owned(),
                placement_json(),
                fixture.to_string_lossy().into_owned(),
            ],
        ] {
            let args = parse_args_from(arguments).unwrap();
            assert_eq!(args.window_placement.unwrap().x, 1024);
        }
        std::fs::remove_file(fixture).unwrap();
    }

    #[test]
    fn rejects_non_chm_and_bad_command_line_shapes() {
        assert!(parse_args_from(vec![manifest_path()]).is_err());
        assert!(parse_args_from(vec!["--unknown".to_owned()]).is_err());
        assert!(parse_args_from(vec![manifest_path(), manifest_path()]).is_err());
    }

    #[test]
    fn safe_join_rejects_escape_paths() {
        let root = Path::new("web");
        assert_eq!(
            safe_join(root, "/src/app.js"),
            Some(root.join("src/app.js"))
        );
        assert!(safe_join(root, "/../secret").is_none());
        assert!(safe_join(root, "/src\\secret").is_none());
    }
}
