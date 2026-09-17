//! excel-view：Inf-Dir QuickView 的 Excel 表格查看器。
//!
//! 架构：一个 winit 窗口 + wry(WebView2) 表面，加载随 exe 发布的
//! `excel-view-web/` 静态资源（@silurus/ooxml 渲染器 + index.html）。
//! 页面通过自定义协议 `excel-view://` 取静态资源与目标文档字节。
//! OOXML 表格直接渲染；`xls/xlt/xlsb/ods/ots` 先用共享的 LibreOffice 运行时
//! 转成 OOXML，再把转换结果交给同一个渲染器。

use std::borrow::Cow;
use std::path::{Path, PathBuf};

use conversion::{prepare_document, PreparedDocument};
use dpi::{LogicalSize, PhysicalPosition, PhysicalSize};
use http::{header, Request, Response, StatusCode};
use percent_encoding::{percent_decode_str, percent_encode, NON_ALPHANUMERIC};
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};
use winit::application::ApplicationHandler;
use winit::event::WindowEvent;
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::window::{Window, WindowId};
use wry::WebViewBuilder;

mod conversion;

// 自定义协议伪装成 http://excel-view.local/：该域名无 DNS 记录，
// WebView2 在网络层之前拦截。Chromium 的 fetch()/Worker/wasm 只认
// http(s) 源，非标准 scheme（如 excel-view://）会 Failed to fetch。
const SCHEME: &str = "http";
const HOST: &str = "excel-view.local";
const WEB_DIR_NAME: &str = "excel-view-web";
const WINDOW_TITLE_SUFFIX: &str = "Excel 查看器";

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
        format!("用法: excel-view.exe <file> [{WINDOW_PLACEMENT_ARGUMENT} <JSON>]")
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
        }
    }
    candidates.push(PathBuf::from(WEB_DIR_NAME));
    candidates
        .into_iter()
        .find(|dir| dir.join("index.html").is_file())
}

fn is_supported(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| conversion::is_supported(&ext.to_ascii_lowercase()))
}

fn response(status: StatusCode, mime: &str, body: Vec<u8>) -> Response<Cow<'static, [u8]>> {
    Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, mime)
        .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
        .body(Cow::Owned(body))
        .unwrap_or_default()
}

fn html_page(body: String) -> Response<Cow<'static, [u8]>> {
    response(
        StatusCode::OK,
        "text/html; charset=utf-8",
        body.into_bytes(),
    )
}

fn escape_html(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// 打开失败时自绘一个错误页，而不是让查看器进程直接退出：宿主正在等这个窗口
/// 出现，退出只会换来一次静默超时。
fn error_page(message: &str) -> Response<Cow<'static, [u8]>> {
    html_page(format!(
        r#"<!doctype html><html lang="zh-CN"><head><meta charset="utf-8" />
<title>{WINDOW_TITLE_SUFFIX}</title><style>
html,body{{margin:0;height:100%;display:flex;align-items:center;justify-content:center;
background:#e8eaed;color:#444;font:14px/1.6 "Segoe UI","Microsoft YaHei",sans-serif;}}
p{{max-width:640px;padding:0 24px;white-space:pre-wrap;}}</style></head>
<body><p>{}</p></body></html>"#,
        escape_html(message)
    ))
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

fn query_value(uri: &http::Uri, key: &str) -> String {
    uri.query()
        .and_then(|query| {
            query.split('&').find_map(|pair| {
                let (name, value) = pair.split_once('=')?;
                (name == key).then_some(value)
            })
        })
        .map(|value| percent_decode_str(value).decode_utf8_lossy().into_owned())
        .unwrap_or_default()
}

fn handle_request(req: Request<Vec<u8>>, web_root: &Path) -> Response<Cow<'static, [u8]>> {
    let uri = req.uri();
    let path = uri.path();

    // /file?path=<编码后的文件路径>：把目标文档字节交给页面
    if path == "/file" {
        let file_path = query_value(uri, "path");
        return match std::fs::read(&file_path) {
            Ok(bytes) => response(StatusCode::OK, "application/octet-stream", bytes),
            Err(e) => response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                format!("读取文件失败: {file_path}\n{e}").into_bytes(),
            ),
        };
    }

    // / ：直接返回外壳页，省掉一次跳转
    if path.is_empty() || path == "/" {
        return match std::fs::read(web_root.join("index.html")) {
            Ok(bytes) => response(StatusCode::OK, "text/html; charset=utf-8", bytes),
            Err(_) => response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                b"404: index.html".to_vec(),
            ),
        };
    }

    match safe_join(web_root, path) {
        Some(target) => match std::fs::read(&target) {
            Ok(bytes) => response(StatusCode::OK, mime_for(&target), bytes),
            Err(_) => response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                format!("404: {path}").into_bytes(),
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
    /// 转换得到的临时文件由它持有，Drop 时清理，所以必须活到进程退出。
    prepared: PreparedDocument,
    window: Option<Window>,
    webview: Option<wry::WebView>,
}

impl ApplicationHandler for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }

        let mut attributes = Window::default_attributes()
            .with_title(format!(
                "{} - {WINDOW_TITLE_SUFFIX}",
                self.prepared.display_name
            ))
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
                eprintln!("[excel-view] 创建窗口失败: {e}");
                std::process::exit(1);
            }
        };

        let root = self.web_root.clone();
        let served_path = self.prepared.file_path.to_string_lossy();
        let display_name = &self.prepared.display_name;
        let start_url = format!(
            "{SCHEME}://{HOST}/index.html?path={}&name={}",
            percent_encode(served_path.as_bytes(), NON_ALPHANUMERIC),
            percent_encode(display_name.as_bytes(), NON_ALPHANUMERIC),
        );

        let webview = match WebViewBuilder::new()
            .with_custom_protocol(SCHEME.into(), move |_id, req| handle_request(req, &root))
            .with_url(&start_url)
            .build(&window)
        {
            Ok(wv) => wv,
            Err(e) => {
                eprintln!("[excel-view] WebView 初始化失败: {e}");
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

/// 在没有文档可显示时报告致命错误：仍然开一个窗口，因为宿主正在等这个窗口出现。
fn run_error_window(message: String, placement: Option<WindowPlacement>) -> ! {
    struct ErrorApp {
        message: String,
        placement: Option<WindowPlacement>,
        window: Option<Window>,
        webview: Option<wry::WebView>,
    }
    impl ApplicationHandler for ErrorApp {
        fn resumed(&mut self, event_loop: &ActiveEventLoop) {
            if self.window.is_some() {
                return;
            }
            let mut attributes = Window::default_attributes()
                .with_title(format!("无法打开 - {WINDOW_TITLE_SUFFIX}"))
                .with_min_inner_size(LogicalSize::new(480u32, 360u32))
                .with_visible(false);
            if let Some(placement) = self.placement {
                attributes = attributes
                    .with_position(PhysicalPosition::new(placement.x, placement.y))
                    .with_inner_size(PhysicalSize::new(
                        placement.client_width,
                        placement.client_height,
                    ));
            } else {
                attributes = attributes.with_inner_size(LogicalSize::new(720u32, 420u32));
            }
            let window = match event_loop.create_window(attributes) {
                Ok(window) => window,
                Err(e) => {
                    eprintln!("[excel-view] 创建窗口失败: {e}");
                    std::process::exit(1);
                }
            };
            let message = self.message.clone();
            let webview = match WebViewBuilder::new()
                .with_custom_protocol(SCHEME.into(), move |_id, _req| error_page(&message))
                .with_url(format!("{SCHEME}://{HOST}/"))
                .build(&window)
            {
                Ok(webview) => webview,
                Err(e) => {
                    eprintln!("[excel-view] WebView 初始化失败: {e}");
                    std::process::exit(1);
                }
            };
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
            if matches!(event, WindowEvent::CloseRequested) {
                event_loop.exit();
            }
        }
    }

    let mut app = ErrorApp {
        message,
        placement,
        window: None,
        webview: None,
    };
    let _ = EventLoop::new().map(|loop_| loop_.run_app(&mut app));
    std::process::exit(1);
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
            eprintln!("[excel-view] 找不到 {WEB_DIR_NAME}/ 资源目录（应位于 exe 旁边）");
            std::process::exit(1);
        }
    };

    if !is_supported(&args.file) {
        run_error_window("不支持的文件类型。".to_string(), args.window_placement);
    }

    // 转换发生在建窗之前：宿主只在窗口出现后才接管它，先建窗会让用户把
    // LibreOffice 的等待时间看成一次白屏。
    let prepared = match prepare_document(&args.file) {
        Ok(prepared) => prepared,
        Err(message) => {
            eprintln!("[excel-view] {message}");
            run_error_window(message, args.window_placement);
        }
    };

    let event_loop = match EventLoop::new() {
        Ok(el) => el,
        Err(e) => {
            eprintln!("[excel-view] 事件循环初始化失败: {e}");
            std::process::exit(1);
        }
    };
    let mut app = App {
        args,
        web_root,
        prepared,
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

    #[test]
    fn only_spreadsheets_are_accepted() {
        assert!(is_supported(Path::new("C:\\data\\Book.XLSB")));
        assert!(!is_supported(Path::new("C:\\data\\Report.docx")));
        assert!(!is_supported(Path::new("C:\\data\\deck.pptx")));
        assert!(!is_supported(Path::new("C:\\data\\notes.txt")));
    }

    #[test]
    fn error_page_escapes_the_message() {
        let page =
            String::from_utf8_lossy(error_page("<script>alert(1)</script>").body().as_ref())
                .into_owned();
        assert!(!page.contains("<script>"));
        assert!(page.contains("&lt;script&gt;"));
    }
}
