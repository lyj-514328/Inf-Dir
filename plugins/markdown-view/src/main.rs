//! markdown-view：Inf-Dir QuickView 的 Markdown 查看器（GFM 兼容）。
//!
//! 架构：一个 winit 窗口 + wry(WebView2) 表面，加载随 exe 发布的
//! `markdown-view-web/` 静态资源（markdown-it / highlight.js / KaTeX /
//! github-markdown-css / mermaid）。页面通过自定义协议取静态资源与目标文档字节。

use std::path::{Path, PathBuf};
use std::sync::Arc;

use http::{Request, StatusCode};
use percent_encoding::{percent_decode_str, percent_encode, NON_ALPHANUMERIC};
use serde::Deserialize;
use viewer_web_shell::{mime_for, response, safe_join, WebViewConfig};
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};

// 自定义协议伪装成 http://markdown-view.local/：该域名无 DNS 记录，
// WebView2 在网络层之前拦截。
const SCHEME: &str = "http";
const HOST: &str = "markdown-view.local";
const WEB_DIR_NAME: &str = "markdown-view-web";
const SW_SHOWNORMAL: i32 = 1;

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
enum IpcMessage {
    /// 用系统默认程序打开本地文件/文件夹
    Open { path: String },
    /// 用默认浏览器打开外部 URL
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
    let op = wide("open");
    let file = wide(target);
    unsafe {
        ShellExecuteW(
            std::ptr::null_mut(),
            op.as_ptr(),
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
            shell_open(&url)
        }
        Ok(IpcMessage::OpenUrl { url }) => {
            eprintln!("[markdown-view] 拒绝打开 URL: {url}");
        }
        Err(e) => {
            eprintln!("[markdown-view] IPC 解析失败: {e}: {}", req.body());
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
        format!("用法: markdown-view.exe <file> [{WINDOW_PLACEMENT_ARGUMENT} <JSON>]")
    })?;
    if !file.is_file() {
        return Err(format!("文件不存在: {}", file.display()));
    }
    Ok(Args {
        file,
        window_placement,
    })
}

/// 资源目录定位：优先 exe 旁边的 markdown-view-web/，其次当前目录。
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

fn handle_request(
    req: Request<Vec<u8>>,
    web_root: &Path,
    document_root: &Path,
) -> viewer_web_shell::WebResponse {
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
        let target = if Path::new(file_path.as_ref()).is_absolute() {
            PathBuf::from(file_path.as_ref())
        } else {
            let Some(target) = safe_join(document_root, &file_path) else {
                return response(
                    StatusCode::FORBIDDEN,
                    "text/plain; charset=utf-8",
                    b"path is outside the Markdown directory".to_vec(),
                );
            };
            target
        };
        if target.as_os_str().is_empty() {
            return response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                b"file path is empty".to_vec(),
            );
        }
        let Ok(canonical) = target.canonicalize() else {
            return response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                format!("读取文件失败: {file_path}").into_bytes(),
            );
        };
        if !canonical.starts_with(document_root) {
            return response(
                StatusCode::FORBIDDEN,
                "text/plain; charset=utf-8",
                b"path is outside the Markdown directory".to_vec(),
            );
        }
        return match std::fs::read(&canonical) {
            Ok(bytes) => response(StatusCode::OK, mime_for(&canonical), bytes),
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

fn main() {
    let args = match parse_args() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("[markdown-view] {e}");
            std::process::exit(1);
        }
    };
    let web_root = match resolve_web_root() {
        Some(r) => r,
        None => {
            eprintln!("[markdown-view] 找不到 {WEB_DIR_NAME}/ 资源目录（应位于 exe 旁边）");
            std::process::exit(1);
        }
    };

    let source_file = match args.file.canonicalize() {
        Ok(path) => path,
        Err(error) => {
            eprintln!("[markdown-view] 文件路径解析失败: {error}");
            std::process::exit(1);
        }
    };
    let document_root = source_file.parent().unwrap_or(Path::new(".")).to_path_buf();
    let file_display = source_file.to_string_lossy();
    let file_query = percent_encode(file_display.as_bytes(), NON_ALPHANUMERIC);
    let router_root = web_root.clone();
    let router_doc = document_root.clone();
    let router = Arc::new(move |request| handle_request(request, &router_root, &router_doc));
    let ipc = Arc::new(handle_ipc);
    let config = WebViewConfig {
        title: format!("{} - Markdown 查看器", source_file.display()),
        host: HOST.to_owned(),
        scheme: SCHEME.to_owned(),
        start_url: format!("{SCHEME}://{HOST}/index.html?path={file_query}"),
        window_placement: args.window_placement,
        request_handler: router,
        ipc_handler: Some(ipc),
    };
    if let Err(error) = viewer_web_shell::run(config) {
        eprintln!("[markdown-view] {error}");
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
