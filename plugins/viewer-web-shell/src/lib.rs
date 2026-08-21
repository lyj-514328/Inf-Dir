use std::borrow::Cow;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use dpi::{LogicalSize, PhysicalPosition, PhysicalSize};
use http::{header, Request, Response, StatusCode};
use viewer_window_placement::WindowPlacement;
use winit::application::ApplicationHandler;
use winit::event::{ElementState, KeyEvent, WindowEvent};
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::window::{Window, WindowId};
use wry::WebViewBuilder;

pub type Body = Cow<'static, [u8]>;
pub type WebResponse = Response<Body>;
pub type RequestHandler = Arc<dyn Fn(Request<Vec<u8>>) -> WebResponse + Send + Sync>;
pub type IpcHandler = Arc<dyn Fn(Request<String>) + Send + Sync>;

pub struct WebViewConfig {
    pub title: String,
    pub host: String,
    pub scheme: String,
    pub start_url: String,
    pub window_placement: Option<WindowPlacement>,
    pub request_handler: RequestHandler,
    pub ipc_handler: Option<IpcHandler>,
}

pub fn run(config: WebViewConfig) -> Result<(), String> {
    let event_loop = EventLoop::new().map_err(|error| error.to_string())?;
    let mut app = App {
        config: Some(config),
        window: None,
        webview: None,
    };
    event_loop
        .run_app(&mut app)
        .map_err(|error| error.to_string())
}

struct App {
    config: Option<WebViewConfig>,
    window: Option<Window>,
    webview: Option<wry::WebView>,
}

impl ApplicationHandler for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }
        let Some(config) = self.config.take() else {
            return;
        };

        let start_maximized = config
            .window_placement
            .is_some_and(|placement| placement.maximized);
        let mut attributes = Window::default_attributes()
            .with_title(config.title)
            .with_min_inner_size(LogicalSize::new(480u32, 360u32))
            .with_visible(false);
        if let Some(placement) = config.window_placement {
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
                eprintln!("[viewer-web-shell] failed to create window: {error}");
                event_loop.exit();
                return;
            }
        };

        let allowed_origin = format!("{}://{}.{}/", config.scheme, config.scheme, config.host);
        let request_handler = config.request_handler.clone();
        let mut builder = WebViewBuilder::new()
            .with_custom_protocol(config.scheme.clone(), move |_id, request| {
                (request_handler)(request)
            })
            .with_navigation_handler(move |url| url.starts_with(&allowed_origin));
        if let Some(ipc_handler) = config.ipc_handler {
            builder = builder.with_ipc_handler(move |request| (ipc_handler)(request));
        }

        let webview = match builder.with_url(&config.start_url).build(&window) {
            Ok(webview) => webview,
            Err(error) => {
                eprintln!("[viewer-web-shell] failed to initialize WebView2: {error}");
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

pub fn response(status: StatusCode, mime: &str, body: Vec<u8>) -> WebResponse {
    Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, mime)
        .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
        .header(header::X_CONTENT_TYPE_OPTIONS, "nosniff")
        .body(Cow::Owned(body))
        .unwrap_or_default()
}

pub fn safe_join(root: &Path, relative: &str) -> Option<PathBuf> {
    let decoded = percent_encoding::percent_decode_str(relative.trim_start_matches('/'))
        .decode_utf8()
        .ok()?;
    let mut result = root.to_path_buf();
    for segment in decoded.split('/') {
        if segment.is_empty() || segment == "." {
            continue;
        }
        if segment == ".." || segment.contains(['\\', ':', '\0']) {
            return None;
        }
        result.push(segment);
    }
    Some(result)
}

pub fn mime_for(path: &Path) -> &'static str {
    let extension = path
        .extension()
        .and_then(|value| value.to_str())
        .map(|value| value.to_ascii_lowercase());
    match extension.as_deref() {
        Some("html") | Some("htm") | Some("xhtml") => "text/html; charset=utf-8",
        Some("mht") | Some("mhtml") => "multipart/related",
        Some("xml") | Some("xsl") | Some("xslt") => "application/xml; charset=utf-8",
        Some("js") | Some("mjs") => "text/javascript; charset=utf-8",
        Some("css") => "text/css; charset=utf-8",
        Some("json") => "application/json; charset=utf-8",
        Some("svg") => "image/svg+xml",
        Some("svgz") => "image/svg+xml",
        Some("png") => "image/png",
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("webp") => "image/webp",
        Some("avif") => "image/avif",
        Some("bmp") => "image/bmp",
        Some("ico") => "image/x-icon",
        Some("woff2") => "font/woff2",
        Some("woff") => "font/woff",
        Some("ttf") => "font/ttf",
        Some("otf") => "font/otf",
        _ => "application/octet-stream",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn safe_join_blocks_path_escape() {
        let root = Path::new("web");
        assert_eq!(
            safe_join(root, "/assets/app.js"),
            Some(root.join("assets/app.js"))
        );
        assert!(safe_join(root, "/../secret").is_none());
        assert!(safe_join(root, "/assets\\secret").is_none());
    }

    #[test]
    fn mime_table_covers_web_assets() {
        assert_eq!(mime_for(Path::new("page.html")), "text/html; charset=utf-8");
        assert_eq!(mime_for(Path::new("image.svg")), "image/svg+xml");
        assert_eq!(mime_for(Path::new("archive.mhtml")), "multipart/related");
    }
}
