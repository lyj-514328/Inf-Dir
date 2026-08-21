//! Inf-Dir CHM Quick View host.
//!
//! The CHMate JavaScript reader is served as static WebView2 content. The
//! custom protocol exposes the single CHM path supplied on the command line;
//! it does not accept arbitrary file paths from the page.

use std::borrow::Cow;
use std::path::{Path, PathBuf};

use dpi::{LogicalSize, PhysicalPosition, PhysicalSize};
use http::{header, Request, Response, StatusCode};
use percent_encoding::{percent_decode_str, percent_encode, NON_ALPHANUMERIC};
use serde::Deserialize;
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};
use winit::application::ApplicationHandler;
use winit::event::{ElementState, KeyEvent, WindowEvent};
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::window::{Window, WindowId};
use wry::WebViewBuilder;

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

fn response(status: StatusCode, mime: &str, body: Vec<u8>) -> Response<Cow<'static, [u8]>> {
    Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, mime)
        .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
        .body(Cow::Owned(body))
        .unwrap_or_default()
}

fn mime_for(path: &Path) -> &'static str {
    let extension = path
        .extension()
        .and_then(|value| value.to_str())
        .map(|value| value.to_ascii_lowercase());
    match extension.as_deref() {
        Some("html") | Some("htm") => "text/html; charset=utf-8",
        Some("js") | Some("mjs") => "text/javascript; charset=utf-8",
        Some("css") => "text/css; charset=utf-8",
        Some("json") => "application/json",
        Some("svg") => "image/svg+xml",
        Some("png") => "image/png",
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("webp") => "image/webp",
        Some("avif") => "image/avif",
        Some("woff2") => "font/woff2",
        Some("woff") => "font/woff",
        Some("ttf") => "font/ttf",
        _ => "application/octet-stream",
    }
}

fn safe_join(root: &Path, relative: &str) -> Option<PathBuf> {
    let decoded = percent_decode_str(relative.trim_start_matches('/'))
        .decode_utf8()
        .ok()?;
    let mut output = root.to_path_buf();
    for segment in decoded.split('/') {
        if segment.is_empty() || segment == "." {
            continue;
        }
        if segment == ".." || segment.contains('\0') || segment.contains('\\') {
            return None;
        }
        output.push(segment);
    }
    Some(output)
}

fn handle_request(
    req: Request<Vec<u8>>,
    web_root: &Path,
    source_file: &Path,
) -> Response<Cow<'static, [u8]>> {
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

struct App {
    args: Args,
    web_root: PathBuf,
    window: Option<Window>,
    webview: Option<wry::WebView>,
}

impl ApplicationHandler for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }

        let name = self
            .args
            .file
            .file_name()
            .map(|value| value.to_string_lossy().into_owned())
            .unwrap_or_else(|| self.args.file.display().to_string());
        let mut attributes = Window::default_attributes()
            .with_title(format!("{name} - CHM Viewer"))
            .with_min_inner_size(LogicalSize::new(480u32, 360u32))
            .with_visible(false);
        let start_maximized = self
            .args
            .window_placement
            .is_some_and(|placement| placement.maximized);
        if let Some(placement) = self.args.window_placement {
            attributes = attributes
                .with_position(PhysicalPosition::new(placement.x, placement.y))
                .with_inner_size(PhysicalSize::new(
                    placement.client_width,
                    placement.client_height,
                ));
        } else {
            attributes = attributes.with_inner_size(LogicalSize::new(960u32, 720u32));
        }

        let window = match event_loop.create_window(attributes) {
            Ok(window) => window,
            Err(error) => {
                eprintln!("[chm-view] failed to create window: {error}");
                std::process::exit(1);
            }
        };

        let root = self.web_root.clone();
        let source_file = self.args.file.clone();
        // Keep this relative to the rewritten WebView2 origin. An original
        // `http://chm-view.local/file` URL would bypass Wry's protocol route.
        let file_url = "/file";
        let file_query = percent_encode(file_url.as_bytes(), NON_ALPHANUMERIC);
        let name_query = percent_encode(name.as_bytes(), NON_ALPHANUMERIC);
        let start_url = format!("{SCHEME}://{HOST}/index.html?file={file_query}&name={name_query}");
        // WebView2 rewrites the custom `http://` protocol to
        // `http://http.<host>/...` before navigation filtering.
        let allowed_origin = format!("{SCHEME}://{SCHEME}.{HOST}/");
        let webview = match WebViewBuilder::new()
            .with_custom_protocol(SCHEME.into(), move |_id, request| {
                handle_request(request, &root, &source_file)
            })
            .with_navigation_handler(move |url| url.starts_with(&allowed_origin))
            .with_ipc_handler(handle_ipc)
            .with_url(&start_url)
            .build(&window)
        {
            Ok(webview) => webview,
            Err(error) => {
                eprintln!("[chm-view] failed to initialize WebView2: {error}");
                std::process::exit(1);
            }
        };

        if start_maximized {
            window.set_maximized(true);
        }
        window.set_visible(true);
        window.focus_window();
        self.window = Some(window);
        self.webview = Some(webview);
    }

    fn window_event(
        &mut self,
        event_loop: &ActiveEventLoop,
        _window_id: WindowId,
        event: WindowEvent,
    ) {
        match event {
            WindowEvent::KeyboardInput {
                event:
                    KeyEvent {
                        physical_key: PhysicalKey::Code(KeyCode::Escape),
                        state: ElementState::Pressed,
                        ..
                    },
                ..
            }
            | WindowEvent::CloseRequested => event_loop.exit(),
            _ => {}
        }
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
    let event_loop = match EventLoop::new() {
        Ok(event_loop) => event_loop,
        Err(error) => {
            eprintln!("[chm-view] failed to initialize event loop: {error}");
            std::process::exit(1);
        }
    };
    let mut app = App {
        args,
        web_root,
        window: None,
        webview: None,
    };
    let _ = event_loop.run_app(&mut app);
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
