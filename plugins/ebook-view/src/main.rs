mod conversion;
mod tcr;

use std::borrow::Cow;
use std::path::{Path, PathBuf};

use conversion::{prepare_document, PreparedDocument};
use dpi::{LogicalSize, PhysicalPosition, PhysicalSize};
use http::{header, Request, Response, StatusCode};
use percent_encoding::{percent_decode_str, percent_encode, AsciiSet, NON_ALPHANUMERIC};
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};
use winit::application::ApplicationHandler;
use winit::event::{ElementState, KeyEvent, WindowEvent};
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::window::{Window, WindowId};
use wry::{WebContext, WebViewBuilder};

const SCHEME: &str = "http";
const HOST: &str = "ebook-view.local";
/// foliate-js checkout (a git submodule): the parsers plus the reader UI it
/// ships for them. Inf-Dir never writes into it, so it stays an unmodified
/// dependency that any checkout of the recorded commit can reproduce.
const WEB_DIR_NAME: &str = "ebook-view-web";
/// Inf-Dir's own reader pages, resolved before [`WEB_DIR_NAME`].
///
/// foliate-js picks a parser from the book itself and has none for the HTML a
/// `.tcr` file decompresses to, so that document needs a page of our own.
const READER_DIR_NAME: &str = "ebook-view-reader";
/// foliate-js ships its own reader UI; we only have to point it at the book.
const READER_PAGE: &str = "reader.html";
/// Page for documents foliate-js cannot parse itself, served from
/// [`READER_DIR_NAME`].
const HTML_READER_PAGE: &str = "text.html";
/// Route serving the single book handed to us on the command line.
const FILE_ROUTE: &str = "/file/";

/// Characters left literal in the book file name segment of [`FILE_ROUTE`].
/// foliate-js derives the book file name from `new URL(res.url).pathname` and
/// detects CBZ/FB2/FBZ with `name.endsWith(...)`, so the extension has to stay
/// readable instead of being percent-encoded.
const FILE_NAME_SET: &AsciiSet = &NON_ALPHANUMERIC
    .remove(b'.')
    .remove(b'-')
    .remove(b'_')
    .remove(b'~');

/// Characters left literal inside the `?url=` query value. The value is itself
/// a URL path, so `/` survives, and `%` is encoded so the reader's single
/// `URLSearchParams` decode restores exactly the path built by [`book_route`].
const QUERY_VALUE_SET: &AsciiSet = &NON_ALPHANUMERIC
    .remove(b'/')
    .remove(b'.')
    .remove(b'-')
    .remove(b'_')
    .remove(b'~');

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
        format!("Usage: ebook-view.exe <FILE> [{WINDOW_PLACEMENT_ARGUMENT} <JSON>]")
    })?;
    if !file.is_file() {
        return Err(format!("file does not exist: {}", file.display()));
    }

    Ok(Args {
        file,
        window_placement,
    })
}

fn webview_data_directory() -> PathBuf {
    std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join("Inf-Dir")
        .join("WebView2")
        .join("ebook-view")
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

fn extension(path: &Path) -> Option<String> {
    path.extension()
        .and_then(|extension| extension.to_str())
        .map(|extension| extension.to_ascii_lowercase())
}

fn mime_for(path: &Path) -> &'static str {
    match extension(path).as_deref() {
        Some("html") => "text/html; charset=utf-8",
        Some("mjs") | Some("js") => "text/javascript; charset=utf-8",
        Some("css") => "text/css; charset=utf-8",
        Some("json") => "application/json; charset=utf-8",
        Some("wasm") => "application/wasm",
        Some("svg") => "image/svg+xml",
        Some("gif") => "image/gif",
        Some("png") => "image/png",
        Some("ttf") => "font/ttf",
        Some("otf") => "font/otf",
        Some("woff2") => "font/woff2",
        Some("woff") => "font/woff",
        _ => "application/octet-stream",
    }
}

/// Path the book is served from: `/file/<book file name>`. The name is carried
/// verbatim (minus percent-encoding) because foliate-js uses its extension to
/// pick the parser and as the fallback title for comic books.
fn book_route(file: &Path) -> String {
    let name = file
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default();
    format!(
        "{FILE_ROUTE}{}",
        percent_encode(name.as_bytes(), FILE_NAME_SET)
    )
}

/// Start URL handed to WebView2. Both reader pages read `?url=` and pass it to
/// `fetch`, which is why the route is encoded a second time for the query.
fn reader_url(page: &str, route: &str) -> String {
    let value = percent_encode(route.as_bytes(), QUERY_VALUE_SET);
    format!("{SCHEME}://{HOST}/{page}?url={value}")
}

/// Reader page that can open `prepared`. foliate-js parses every format we
/// hand it except the HTML produced for `.tcr`.
fn reader_page(prepared: &PreparedDocument) -> &'static str {
    if prepared.mime_type.starts_with("text/html") {
        HTML_READER_PAGE
    } else {
        READER_PAGE
    }
}

/// A request path as a root-relative path, or `None` when it is not valid
/// UTF-8 or tries to escape the web roots.
fn request_path(path: &str) -> Option<PathBuf> {
    let decoded = percent_decode_str(path.trim_start_matches('/'))
        .decode_utf8()
        .ok()?;
    let mut relative = PathBuf::new();
    for segment in decoded.split('/') {
        if segment.is_empty() || segment == "." {
            continue;
        }
        if segment == ".." || segment.contains(['\\', ':']) {
            return None;
        }
        relative.push(segment);
    }
    Some(relative)
}

/// Static assets of a running viewer.
///
/// A page of ours takes precedence over the foliate-js library, so Inf-Dir's
/// own pages can sit beside the checkout and still import the modules in it.
#[derive(Clone)]
struct WebRoots {
    reader: Option<PathBuf>,
    library: Option<PathBuf>,
}

impl WebRoots {
    /// Directory holding `marker`, either beside the executable or, for the
    /// development layout, relative to the working directory.
    fn locate(name: &str, marker: &str) -> Option<PathBuf> {
        let mut candidates = Vec::new();
        if let Ok(exe) = std::env::current_exe() {
            if let Some(directory) = exe.parent() {
                candidates.push(directory.join(name));
            }
        }
        candidates.push(PathBuf::from(name));
        candidates
            .into_iter()
            .find(|directory| directory.join(marker).is_file())
    }

    fn discover() -> Self {
        Self {
            reader: Self::locate(READER_DIR_NAME, HTML_READER_PAGE),
            library: Self::locate(WEB_DIR_NAME, READER_PAGE),
        }
    }

    /// Existing file a request resolves to, preferring Inf-Dir's own pages.
    fn find(&self, request: &str) -> Option<PathBuf> {
        let relative = request_path(request)?;
        [self.reader.as_deref(), self.library.as_deref()]
            .into_iter()
            .flatten()
            .map(|root| root.join(&relative))
            .find(|target| target.is_file())
    }
}

fn not_found(relative: &str) -> Response<Cow<'static, [u8]>> {
    response(
        StatusCode::NOT_FOUND,
        "text/plain; charset=utf-8",
        format!("404: {relative}").into_bytes(),
    )
}

fn handle_request(
    request: Request<Vec<u8>>,
    roots: &WebRoots,
    prepared: &PreparedDocument,
) -> Response<Cow<'static, [u8]>> {
    let path = request.uri().path();
    if path.starts_with(FILE_ROUTE) {
        return match std::fs::read(&prepared.file_path) {
            Ok(bytes) => response(StatusCode::OK, prepared.mime_type, bytes),
            Err(error) => response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                format!("Could not read {}\n{error}", prepared.file_path.display()).into_bytes(),
            ),
        };
    }

    let relative = if path.is_empty() || path == "/" {
        READER_PAGE
    } else {
        path
    };
    match roots.find(relative) {
        Some(target) => match std::fs::read(&target) {
            Ok(bytes) => response(StatusCode::OK, mime_for(&target), bytes),
            Err(_) => not_found(relative),
        },
        None => not_found(relative),
    }
}

struct App {
    args: Args,
    prepared: Option<PreparedDocument>,
    roots: WebRoots,
    window: Option<Window>,
    webview: Option<wry::WebView>,
    web_context: WebContext,
}

impl ApplicationHandler for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }

        let prepared = match prepare_document(&self.args.file) {
            Ok(p) => p,
            Err(error) => {
                eprintln!("[ebook-view] document preparation failed: {error}");
                event_loop.exit();
                return;
            }
        };

        let page = reader_page(&prepared);
        if page == HTML_READER_PAGE && self.roots.reader.is_none() {
            eprintln!("[ebook-view] could not find {READER_DIR_NAME} beside the executable");
            event_loop.exit();
            return;
        }

        let title_name = &prepared.display_name;
        let mut attributes = Window::default_attributes()
            .with_title(format!("{title_name} - Ebook Viewer"))
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
                eprintln!("[ebook-view] failed to create window: {error}");
                event_loop.exit();
                return;
            }
        };

        let roots = self.roots.clone();
        let start_url = reader_url(page, &book_route(&prepared.file_path));
        let served_path = prepared.file_path.clone();
        let served_mime = prepared.mime_type;

        let webview = match WebViewBuilder::new_with_web_context(&mut self.web_context)
            .with_custom_protocol(SCHEME.into(), move |_id, request| {
                let dummy = PreparedDocument::temporary(
                    served_path.clone(),
                    String::new(),
                    served_mime,
                    PathBuf::new(),
                );
                handle_request(request, &roots, &dummy)
            })
            .with_navigation_handler(|url| url.contains(HOST))
            .with_url(&start_url)
            .build(&window)
        {
            Ok(webview) => webview,
            Err(error) => {
                eprintln!("[ebook-view] failed to initialize WebView2: {error}");
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
        self.prepared = Some(prepared);
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
            eprintln!("[ebook-view] {error}");
            std::process::exit(1);
        }
    };
    let roots = WebRoots::discover();
    if roots.library.is_none() {
        eprintln!("[ebook-view] could not find {WEB_DIR_NAME} beside the executable");
        std::process::exit(1);
    }
    let event_loop = match EventLoop::new() {
        Ok(event_loop) => event_loop,
        Err(error) => {
            eprintln!("[ebook-view] failed to create event loop: {error}");
            std::process::exit(1);
        }
    };
    let mut app = App {
        args,
        prepared: None,
        roots,
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
    fn request_path_accepts_nested_static_assets() {
        assert_eq!(
            request_path("/vendor/pdfjs/pdf.worker.mjs"),
            Some(PathBuf::from("vendor").join("pdfjs").join("pdf.worker.mjs"))
        );
        assert_eq!(
            request_path("/ui/tree.js"),
            Some(PathBuf::from("ui").join("tree.js"))
        );
        assert_eq!(
            request_path("/reader.html"),
            Some(PathBuf::from("reader.html"))
        );
    }

    #[test]
    fn request_path_decodes_percent_escapes() {
        assert_eq!(
            request_path("/file/My%20Book.epub"),
            Some(PathBuf::from("file").join("My Book.epub"))
        );
    }

    #[test]
    fn request_path_rejects_parent_and_windows_path_segments() {
        assert_eq!(request_path("/../secret.txt"), None);
        assert_eq!(request_path("/C:/secret.txt"), None);
        assert_eq!(request_path("/folder\\secret.txt"), None);
    }

    #[test]
    fn reader_pages_take_precedence_over_the_library() {
        let base = std::env::temp_dir().join(format!("ebook-view-roots-{}", std::process::id()));
        let reader = base.join("ebook-view-reader");
        let library = base.join("ebook-view-web");
        std::fs::create_dir_all(&reader).unwrap();
        std::fs::create_dir_all(&library).unwrap();
        std::fs::write(reader.join("text.html"), b"reader").unwrap();
        std::fs::write(library.join("reader.html"), b"library").unwrap();
        std::fs::write(library.join("text.html"), b"library").unwrap();

        let roots = WebRoots {
            reader: Some(reader.clone()),
            library: Some(library.clone()),
        };
        assert_eq!(roots.find("/text.html"), Some(reader.join("text.html")));
        assert_eq!(roots.find("/reader.html"), Some(library.join("reader.html")));
        assert_eq!(roots.find("/vendor/zip.js"), None);
        assert_eq!(roots.find("/../secret.txt"), None);

        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn static_mime_types_are_explicit() {
        assert_eq!(
            mime_for(Path::new("reader.js")),
            "text/javascript; charset=utf-8"
        );
        assert_eq!(mime_for(Path::new("jbig2.wasm")), "application/wasm");
        assert_eq!(mime_for(Path::new("Liberation.ttf")), "font/ttf");
        assert_eq!(mime_for(Path::new("data.bin")), "application/octet-stream");
    }

    #[test]
    fn direct_prepared_document_mime() {
        assert_eq!(
            PreparedDocument::direct(PathBuf::from("a.EPUB")).mime_type,
            "application/epub+zip"
        );
        assert_eq!(
            PreparedDocument::direct(PathBuf::from("a.azw3")).mime_type,
            "application/vnd.amazon.ebook"
        );
        assert_eq!(
            PreparedDocument::direct(PathBuf::from("a.cbz")).mime_type,
            "application/vnd.comicbook+zip"
        );
        assert_eq!(
            PreparedDocument::direct(PathBuf::from("a.unknown")).mime_type,
            "application/octet-stream"
        );
    }

    #[test]
    fn foliate_formats_use_the_shipped_reader_page() {
        for name in [
            "a.epub", "a.mobi", "a.azw3", "a.fb2", "a.fbz", "a.cbz", "a.pdf",
        ] {
            let prepared = PreparedDocument::direct(PathBuf::from(name));
            assert_eq!(reader_page(&prepared), READER_PAGE, "{name}");
        }
    }

    #[test]
    fn decompressed_tcr_uses_the_inf_dir_reader_page() {
        let prepared = PreparedDocument::temporary(
            PathBuf::from("novel.html"),
            "novel.tcr".to_string(),
            "text/html; charset=utf-8",
            PathBuf::new(),
        );

        assert_eq!(reader_page(&prepared), HTML_READER_PAGE);
    }

    #[test]
    fn book_route_keeps_the_extension_detectable_by_foliate() {
        assert_eq!(book_route(Path::new(r"C:\books\comic.cbz")), "/file/comic.cbz");
        assert_eq!(
            book_route(Path::new(r"C:\books\My Comic #1.cbz")),
            "/file/My%20Comic%20%231.cbz"
        );
    }

    #[test]
    fn reader_url_survives_the_query_decode() {
        let route = book_route(Path::new(r"C:\books\My Comic #1.cbz"));
        let url = reader_url(READER_PAGE, &route);
        assert_eq!(
            url,
            "http://ebook-view.local/reader.html?url=/file/My%2520Comic%2520%25231.cbz"
        );

        let value = url.split("?url=").nth(1).unwrap();
        let decoded = percent_decode_str(value).decode_utf8().unwrap();
        assert_eq!(decoded, route);
        assert!(decoded.ends_with(".cbz"));
    }

    #[test]
    fn multi_dot_book_names_keep_their_last_extension() {
        let route = book_route(Path::new(r"C:\books\My.Book.v2.epub"));

        assert_eq!(route, "/file/My.Book.v2.epub");
        assert!(percent_decode_str(&route)
            .decode_utf8()
            .unwrap()
            .ends_with(".epub"));
    }

    #[test]
    fn webview_data_is_outside_the_plugin_package() {
        let directory = webview_data_directory();

        assert!(directory.ends_with(Path::new("Inf-Dir/WebView2/ebook-view")));
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
