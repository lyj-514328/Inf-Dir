use std::path::{Path, PathBuf};
use std::sync::Arc;

use http::{header, Request, Response, StatusCode};
use percent_encoding::{percent_encode, NON_ALPHANUMERIC};
use viewer_web_shell::{mime_for, response, safe_join, WebViewConfig};
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};

const SCHEME: &str = "http";
const HOST: &str = "web-view.local";
const WEB_DIR_NAME: &str = "web-view-web";

struct Args {
    file: PathBuf,
    window_placement: Option<WindowPlacement>,
}

fn parse_args() -> Result<Args, String> {
    let mut file = None;
    let mut window_placement = None;
    let mut it = std::env::args().skip(1);
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
        format!("usage: web-view.exe <file> [{WINDOW_PLACEMENT_ARGUMENT} <JSON>]")
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
    if let Ok(executable) = std::env::current_exe() {
        if let Some(directory) = executable.parent() {
            candidates.push(directory.join(WEB_DIR_NAME));
        }
    }
    candidates.push(PathBuf::from(WEB_DIR_NAME));
    candidates
        .into_iter()
        .find(|directory| directory.join("index.html").is_file())
}

fn canonical_root(path: &Path) -> Result<PathBuf, String> {
    path.canonicalize()
        .map_err(|error| format!("failed to resolve {}: {error}", path.display()))
}

fn is_within(path: &Path, root: &Path) -> bool {
    path == root || path.starts_with(root)
}

fn file_response(path: &Path, root: &Path) -> viewer_web_shell::WebResponse {
    let Ok(canonical) = canonical_root(path) else {
        return response(
            StatusCode::NOT_FOUND,
            "text/plain; charset=utf-8",
            b"document not found".to_vec(),
        );
    };
    if !is_within(&canonical, root) || !canonical.is_file() {
        return response(
            StatusCode::FORBIDDEN,
            "text/plain; charset=utf-8",
            b"document path is outside the allowed directory".to_vec(),
        );
    }
    let Ok(bytes) = std::fs::read(&canonical) else {
        return response(
            StatusCode::NOT_FOUND,
            "text/plain; charset=utf-8",
            b"document cannot be read".to_vec(),
        );
    };
    let mime = mime_for(&canonical);
    let mut builder = Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, mime)
        .header(header::X_CONTENT_TYPE_OPTIONS, "nosniff")
        .header(
            header::CONTENT_SECURITY_POLICY,
            "default-src 'self'; base-uri 'none'; object-src 'none'; script-src 'none'; form-action 'none'; frame-src 'none'; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline' blob:; font-src 'self' data: blob:",
        );
    if canonical
        .extension()
        .is_some_and(|extension| extension.eq_ignore_ascii_case("svgz"))
    {
        builder = builder.header(header::CONTENT_ENCODING, "gzip");
    }
    builder
        .body(std::borrow::Cow::Owned(bytes))
        .unwrap_or_default()
}

fn handle_request(
    request: Request<Vec<u8>>,
    web_root: &Path,
    document_root: &Path,
    source_file: &Path,
) -> viewer_web_shell::WebResponse {
    let path = request.uri().path();
    if path == "/file" {
        return file_response(source_file, document_root);
    }
    if let Some(relative) = path.strip_prefix("/document/") {
        return match safe_join(document_root, relative) {
            Some(target) => file_response(&target, document_root),
            None => response(
                StatusCode::BAD_REQUEST,
                "text/plain; charset=utf-8",
                b"invalid document path".to_vec(),
            ),
        };
    }

    let relative = if path.is_empty() || path == "/" {
        "index.html"
    } else {
        path.trim_start_matches('/')
    };
    let Some(target) = safe_join(web_root, relative) else {
        return response(
            StatusCode::BAD_REQUEST,
            "text/plain; charset=utf-8",
            b"invalid resource path".to_vec(),
        );
    };
    match std::fs::read(&target) {
        Ok(bytes) => response(StatusCode::OK, mime_for(&target), bytes),
        Err(_) => response(
            StatusCode::NOT_FOUND,
            "text/plain; charset=utf-8",
            b"resource not found".to_vec(),
        ),
    }
}

fn main() {
    let args = match parse_args() {
        Ok(args) => args,
        Err(error) => {
            eprintln!("[web-view] {error}");
            std::process::exit(1);
        }
    };
    let web_root = match resolve_web_root() {
        Some(root) => root,
        None => {
            eprintln!("[web-view] missing {WEB_DIR_NAME} beside the executable");
            std::process::exit(1);
        }
    };
    let source_file = match canonical_root(&args.file) {
        Ok(path) => path,
        Err(error) => {
            eprintln!("[web-view] {error}");
            std::process::exit(1);
        }
    };
    let document_root = source_file
        .parent()
        .and_then(|path| path.canonicalize().ok())
        .unwrap_or_else(|| PathBuf::from("."));
    let name = source_file
        .file_name()
        .map(|value| value.to_string_lossy().into_owned())
        .unwrap_or_else(|| source_file.display().to_string());
    let encoded_name = percent_encode(name.as_bytes(), NON_ALPHANUMERIC);
    let source_display = source_file.to_string_lossy();
    let encoded_path = percent_encode(source_display.as_bytes(), NON_ALPHANUMERIC);
    let start_url = format!(
        "{SCHEME}://{HOST}/index.html?path={encoded_path}&document=/document/{encoded_name}"
    );
    let router =
        Arc::new(move |request| handle_request(request, &web_root, &document_root, &source_file));
    let config = WebViewConfig {
        title: format!("{name} - 网页查看器"),
        host: HOST.to_owned(),
        scheme: SCHEME.to_owned(),
        start_url,
        window_placement: args.window_placement,
        request_handler: router,
        ipc_handler: None,
    };
    if let Err(error) = viewer_web_shell::run(config) {
        eprintln!("[web-view] {error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_web_document_extensions() {
        for extension in ["svg", "svgz", "html", "htm", "xhtml", "mht", "mhtml"] {
            assert!(!mime_for(Path::new(&format!("file.{extension}"))).is_empty());
        }
    }

    #[test]
    fn safe_join_rejects_escape_paths() {
        let root = Path::new(r"C:\docs");
        assert!(safe_join(root, "images/logo.svg").is_some());
        assert!(safe_join(root, "../secret.html").is_none());
        assert!(safe_join(root, r"C:\secret.html").is_none());
    }
}
