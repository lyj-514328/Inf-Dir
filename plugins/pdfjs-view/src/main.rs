use std::borrow::Cow;
use std::path::{Path, PathBuf};

use dpi::{LogicalSize, PhysicalPosition, PhysicalSize};
use http::{header, Request, Response, StatusCode};
use percent_encoding::{percent_decode_str, percent_encode, NON_ALPHANUMERIC};
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};
use winit::application::ApplicationHandler;
use winit::event::{ElementState, KeyEvent, WindowEvent};
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::window::{Window, WindowId};
use wry::{WebContext, WebViewBuilder};
#[cfg(windows)]
use wry::WebViewBuilderExtWindows;

const SCHEME: &str = "http";
const HOST: &str = "pdfjs-view.local";
const WEB_DIR_NAME: &str = "pdfjs-view-web";

struct Args {
    file: PathBuf,
    window_placement: Option<WindowPlacement>,
}

fn parse_args() -> Result<Args, String> {
    parse_args_from(std::env::args().skip(1))
}

fn parse_args_from(args: impl IntoIterator<Item = String>) -> Result<Args, String> {
    let mut file: Option<PathBuf> = None;
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
                if file.is_some() {
                    return Err(format!("unexpected argument: {arg}"));
                }
                file = Some(PathBuf::from(arg));
            }
        }
    }

    let file = file.ok_or_else(|| {
        format!("Usage: pdfjs-view.exe <FILE> [{WINDOW_PLACEMENT_ARGUMENT} <JSON>]")
    })?;
    if !file.is_file() {
        return Err(format!("file does not exist: {}", file.display()));
    }

    Ok(Args {
        file,
        window_placement,
    })
}

fn resolve_web_root() -> Option<PathBuf> {
    let mut candidates = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        if let Some(directory) = exe.parent() {
            candidates.push(directory.join(WEB_DIR_NAME));
        }
    }
    candidates.push(PathBuf::from(WEB_DIR_NAME));
    candidates
        .into_iter()
        .find(|directory| directory.join("web").join("viewer.html").is_file())
}

fn webview_data_directory() -> PathBuf {
    std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join("Inf-Dir")
        .join("WebView2")
        .join("pdfjs-view")
}

fn response(status: StatusCode, mime: &str, body: Vec<u8>) -> Response<Cow<'static, [u8]>> {
    Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, mime)
        .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
        .header(header::X_CONTENT_TYPE_OPTIONS, "nosniff")
        .body(Cow::Owned(body))
        .unwrap_or_default()
}

fn mime_for(path: &Path) -> &'static str {
    match path
        .extension()
        .and_then(|extension| extension.to_str())
        .map(|extension| extension.to_ascii_lowercase())
        .as_deref()
    {
        Some("html") => "text/html; charset=utf-8",
        Some("mjs") | Some("js") => "text/javascript; charset=utf-8",
        Some("css") => "text/css; charset=utf-8",
        Some("json") => "application/json; charset=utf-8",
        Some("wasm") => "application/wasm",
        Some("svg") => "image/svg+xml",
        Some("gif") => "image/gif",
        Some("png") => "image/png",
        Some("woff2") => "font/woff2",
        Some("woff") => "font/woff",
        _ => "application/octet-stream",
    }
}

fn safe_join(root: &Path, relative: &str) -> Option<PathBuf> {
    let decoded = percent_decode_str(relative.trim_start_matches('/'))
        .decode_utf8()
        .ok()?;
    let mut result = root.to_path_buf();
    for segment in decoded.split('/') {
        if segment.is_empty() || segment == "." {
            continue;
        }
        if segment == ".." || segment.contains(['\\', ':']) {
            return None;
        }
        result.push(segment);
    }
    Some(result)
}

fn handle_request(
    request: Request<Vec<u8>>,
    web_root: &Path,
    target_file: &Path,
) -> Response<Cow<'static, [u8]>> {
    let path = request.uri().path();
    if path == "/file" {
        return match std::fs::read(target_file) {
            Ok(bytes) => response(StatusCode::OK, "application/pdf", bytes),
            Err(error) => response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                format!("Could not read {}\n{error}", target_file.display()).into_bytes(),
            ),
        };
    }

    let relative = if path.is_empty() || path == "/" {
        "web/viewer.html"
    } else {
        path
    };
    match safe_join(web_root, relative) {
        Some(target) => match std::fs::read(&target) {
            Ok(bytes) => response(StatusCode::OK, mime_for(&target), bytes),
            Err(_) => response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                format!("404: {relative}").into_bytes(),
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
    web_context: WebContext,
}

impl ApplicationHandler for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }

        let file_name = self
            .args
            .file
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_else(|| self.args.file.display().to_string());
        let mut attributes = Window::default_attributes()
            .with_title(format!("{file_name} - PDF 查看器"))
            .with_min_inner_size(LogicalSize::new(520u32, 360u32))
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
                eprintln!("[pdfjs-view] failed to create window: {error}");
                event_loop.exit();
                return;
            }
        };

        let web_root = self.web_root.clone();
        let target_file = self.args.file.clone();
        let start_url =
            format!("{SCHEME}://{HOST}/web/viewer.html?file=../file");
        let webview = match WebViewBuilder::new_with_web_context(&mut self.web_context)
            .with_custom_protocol(SCHEME.into(), move |_id, request| {
                handle_request(request, &web_root, &target_file)
            })
            .with_navigation_handler(|url| url.contains(HOST))
            .with_url(&start_url)
            .build(&window)
        {
            Ok(webview) => webview,
            Err(error) => {
                eprintln!("[pdfjs-view] failed to initialize WebView2: {error}");
                event_loop.exit();
                return;
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
            eprintln!("[pdfjs-view] {error}");
            std::process::exit(1);
        }
    };
    let web_root = match resolve_web_root() {
        Some(root) => root,
        None => {
            eprintln!("[pdfjs-view] could not find {WEB_DIR_NAME} beside the executable");
            std::process::exit(1);
        }
    };
    let event_loop = match EventLoop::new() {
        Ok(event_loop) => event_loop,
        Err(error) => {
            eprintln!("[pdfjs-view] failed to create event loop: {error}");
            std::process::exit(1);
        }
    };
    let mut app = App {
        args,
        web_root,
        web_context: WebContext::new(Some(webview_data_directory())),
        window: None,
        webview: None,
    };
    let _ = event_loop.run_app(&mut app);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn safe_join_accepts_nested_static_assets() {
        let root = Path::new(r"C:\viewer\web");

        assert_eq!(
            safe_join(root, "/build/pdf.worker.mjs"),
            Some(root.join("build").join("pdf.worker.mjs"))
        );
        assert_eq!(
            safe_join(root, "/cmaps/UniGB-UCS2-H.bcmap"),
            Some(root.join("cmaps").join("UniGB-UCS2-H.bcmap"))
        );
    }

    #[test]
    fn safe_join_rejects_parent_and_windows_path_segments() {
        let root = Path::new(r"C:\viewer\web");

        assert_eq!(safe_join(root, "/../secret.txt"), None);
        assert_eq!(safe_join(root, "/C:/secret.txt"), None);
        assert_eq!(safe_join(root, "/folder\\secret.txt"), None);
    }

    #[test]
    fn static_mime_types_are_explicit() {
        assert_eq!(
            mime_for(Path::new("viewer.mjs")),
            "text/javascript; charset=utf-8"
        );
        assert_eq!(mime_for(Path::new("jbig2.wasm")), "application/wasm");
        assert_eq!(mime_for(Path::new("data.bin")), "application/octet-stream");
    }

    #[test]
    fn webview_data_is_outside_the_plugin_package() {
        let directory = webview_data_directory();

        assert!(directory.ends_with(Path::new("Inf-Dir/WebView2/pdfjs-view")));
    }

    fn manifest_path() -> String {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("Cargo.toml")
            .to_string_lossy()
            .into_owned()
    }

    fn placement_json() -> String {
        r#"{"version":2,"x":1024,"y":0,"clientWidth":1008,"clientHeight":1113,"maximized":false}"#
            .to_string()
    }

    #[test]
    fn parses_window_placement_before_or_after_file() {
        for arguments in [
            vec![
                manifest_path(),
                WINDOW_PLACEMENT_ARGUMENT.to_string(),
                placement_json(),
            ],
            vec![
                WINDOW_PLACEMENT_ARGUMENT.to_string(),
                placement_json(),
                manifest_path(),
            ],
        ] {
            let args = parse_args_from(arguments).unwrap();
            assert_eq!(args.window_placement.unwrap().x, 1024);
        }
    }

    #[test]
    fn rejects_bad_command_line_shapes() {
        assert!(parse_args_from(vec!["--unknown".to_string()]).is_err());
        assert!(parse_args_from(vec![manifest_path(), manifest_path()]).is_err());
        assert!(
            parse_args_from(vec![manifest_path(), WINDOW_PLACEMENT_ARGUMENT.to_string(),]).is_err()
        );
        assert!(parse_args_from(vec![
            manifest_path(),
            WINDOW_PLACEMENT_ARGUMENT.to_string(),
            placement_json(),
            WINDOW_PLACEMENT_ARGUMENT.to_string(),
            placement_json(),
        ])
        .is_err());
    }
}
