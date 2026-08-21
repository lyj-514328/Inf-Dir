//! excel-view: Inf-Dir QuickView 的 FortuneSheet Excel viewer.
//!
//! 架构：一个 winit 窗口 + wry(WebView2) 表面，加载随 exe 发布的
//! `excel-view-web/` 静态资源（FortuneSheet/FortuneExcel + index.html）。
//! 页面通过自定义 HTTP 协议取静态资源与目标文档字节。

use std::borrow::Cow;
use std::path::{Path, PathBuf};

use dpi::{LogicalSize, PhysicalPosition, PhysicalSize};
use http::{header, Request, Response, StatusCode};
use percent_encoding::{percent_decode_str, percent_encode, NON_ALPHANUMERIC};
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};
use winit::application::ApplicationHandler;
use winit::event::WindowEvent;
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::window::{Window, WindowId};
use wry::WebViewBuilder;

// 自定义协议伪装成 http://excel-view.local/：该域名无 DNS 记录，
// WebView2 在网络层之前拦截。Chromium 的 fetch()/Worker/wasm 只认
// http(s) 源，非标准 scheme 会 Failed to fetch。
const SCHEME: &str = "http";
const HOST: &str = "excel-view.local";
const WEB_DIR_NAME: &str = "excel-view-web";

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
        format!("Usage: excel-view.exe <file> [{WINDOW_PLACEMENT_ARGUMENT} <JSON>]")
    })?;
    if !file.is_file() {
        return Err(format!("文件不存在: {}", file.display()));
    }
    Ok(Args {
        file,
        window_placement,
    })
}

/// 资源目录定位：优先 exe 旁边的 excel-view-web/，其次当前目录。
fn resolve_web_root() -> Option<PathBuf> {
    let mut candidates = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            candidates.push(dir.join(WEB_DIR_NAME));
            let mut ancestor = dir;
            for _ in 0..3 {
                let Some(parent) = ancestor.parent() else { break };
                candidates.push(parent.join(WEB_DIR_NAME));
                ancestor = parent;
            }
        }
    }
    candidates.push(PathBuf::from(WEB_DIR_NAME));
    candidates
        .into_iter()
        .find(|dir| dir.join("index.html").is_file())
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
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase());
    match ext.as_deref() {
        Some("html") => "text/html; charset=utf-8",
        Some("js") | Some("mjs") => "text/javascript; charset=utf-8",
        Some("wasm") => "application/wasm",
        Some("css") => "text/css; charset=utf-8",
        Some("json") => "application/json",
        Some("svg") => "image/svg+xml",
        Some("png") => "image/png",
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        _ => "application/octet-stream",
    }
}

/// 把请求路径安全地拼到资源根目录上，拒绝 `..` 越界。
fn safe_join(root: &Path, rel: &str) -> Option<PathBuf> {
    let decoded = percent_decode_str(rel.trim_start_matches('/'))
        .decode_utf8()
        .ok()?;
    let mut out = root.to_path_buf();
    for seg in decoded.split('/') {
        if seg.is_empty() || seg == "." {
            continue;
        }
        if seg == ".." {
            return None;
        }
        out.push(seg);
    }
    Some(out)
}

fn handle_request(req: Request<Vec<u8>>, web_root: &Path) -> Response<Cow<'static, [u8]>> {
    let uri = req.uri();
    let path = uri.path();

    // /file?path=<编码后的文件路径>：把目标文档字节交给页面
    if path == "/file" {
        let encoded = uri
            .query()
            .and_then(|q| {
                q.split('&').find_map(|kv| {
                    let (k, v) = kv.split_once('=')?;
                    (k == "path").then_some(v)
                })
            })
            .unwrap_or("");
        let file_path = percent_decode_str(encoded).decode_utf8_lossy();
        return match std::fs::read(file_path.as_ref()) {
            Ok(bytes) => response(StatusCode::OK, "application/octet-stream", bytes),
            Err(e) => response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                format!("读取文件失败: {file_path}\n{e}").into_bytes(),
            ),
        };
    }

    let rel = if path.is_empty() || path == "/" {
        "index.html"
    } else {
        path
    };
    match safe_join(web_root, rel) {
        Some(target) => match std::fs::read(&target) {
            Ok(bytes) => response(StatusCode::OK, mime_for(&target), bytes),
            Err(_) => response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                format!("404: {rel}").into_bytes(),
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
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_else(|| self.args.file.display().to_string());

        let mut attributes = Window::default_attributes()
            .with_title(format!("{name} - Excel View"))
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
            Ok(w) => w,
            Err(e) => {
                eprintln!("[excel-view] failed to create window: {e}");
                std::process::exit(1);
            }
        };

        let root = self.web_root.clone();
        let file_display = self.args.file.to_string_lossy();
        let file_query = percent_encode(file_display.as_bytes(), NON_ALPHANUMERIC);
        let start_url = format!("{SCHEME}://{HOST}/index.html?path={file_query}");

        let webview = match WebViewBuilder::new()
            .with_custom_protocol(SCHEME.into(), move |_id, req| handle_request(req, &root))
            .with_url(&start_url)
            .build(&window)
        {
            Ok(wv) => wv,
            Err(e) => {
                eprintln!("[excel-view] failed to initialize WebView2: {e}");
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
            WindowEvent::CloseRequested => {
                event_loop.exit();
            }
            _ => {}
        }
    }
}

fn main() {
    let args = match parse_args() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("[excel-view] {e}");
            std::process::exit(1);
        }
    };
    let web_root = match resolve_web_root() {
        Some(r) => r,
        None => {
            eprintln!("[excel-view] could not find {WEB_DIR_NAME}/ beside the executable");
            std::process::exit(1);
        }
    };

    let event_loop = match EventLoop::new() {
        Ok(el) => el,
        Err(e) => {
            eprintln!("[excel-view] failed to create event loop: {e}");
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
