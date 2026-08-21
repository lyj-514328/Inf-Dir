use std::borrow::Cow;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use dpi::{LogicalSize, PhysicalPosition, PhysicalSize};
use http::{header, Request, Response, StatusCode};
use percent_encoding::percent_decode_str;
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};
use winit::application::ApplicationHandler;
use winit::event::{ElementState, KeyEvent, WindowEvent};
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::window::{Window, WindowId};
use wry::{WebContext, WebViewBuilder};

#[cfg(windows)]
use std::os::windows::process::CommandExt;

const SCHEME: &str = "http";
const HOST: &str = "onlyoffice-view.local";
const WEB_DIR_NAME: &str = "onlyoffice-view-web";
const X2T_TIMEOUT: Duration = Duration::from_secs(120);
const PDF_FORMAT_CODE: &str = "513";
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

const SUPPORTED_EXTENSIONS: &[&str] = &[
    "doc", "docm", "docx", "dot", "dotm", "dotx", "odt", "ott", "fodt", "rtf", "wps", "wbk", "mht",
    "ppt", "pptm", "pptx", "pot", "potm", "potx", "pps", "ppsm", "ppsx", "odp", "otp", "fodp",
    "vsd", "vsdm", "vsdx", "vss", "vssm", "vssx", "vst", "vstm", "vstx", "vdx", "vdw", "vsx",
    "vtx",
];

struct Args {
    file: PathBuf,
    window_placement: Option<WindowPlacement>,
}

struct Conversion {
    directory: PathBuf,
    pdf: PathBuf,
}

fn parse_args() -> Result<Args, String> {
    let mut file = None;
    let mut window_placement = None;
    let mut args = std::env::args().skip(1);

    while let Some(arg) = args.next() {
        match arg.as_str() {
            WINDOW_PLACEMENT_ARGUMENT => {
                if window_placement.is_some() {
                    return Err(format!("duplicate option: {WINDOW_PLACEMENT_ARGUMENT}"));
                }
                let value = args
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
        format!("Usage: onlyoffice-view.exe <FILE> [{WINDOW_PLACEMENT_ARGUMENT} <JSON>]")
    })?;
    if !file.is_file() {
        return Err(format!("file does not exist: {}", file.display()));
    }
    if !is_supported_file(&file) {
        return Err(format!(
            "unsupported Office format: {}",
            file.extension()
                .and_then(|ext| ext.to_str())
                .unwrap_or("<none>")
        ));
    }

    Ok(Args {
        file,
        window_placement,
    })
}

fn is_supported_file(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .map(|extension| {
            let extension = extension.to_ascii_lowercase();
            SUPPORTED_EXTENSIONS.contains(&extension.as_str())
        })
        .unwrap_or(false)
}

fn find_x2t_in(directory: &Path) -> Option<PathBuf> {
    ["x2t.exe", "x2t32.exe", "x2t"]
        .iter()
        .map(|name| directory.join(name))
        .find(|path| path.is_file())
}

fn resolve_x2t() -> Result<(PathBuf, PathBuf), String> {
    let mut candidates = Vec::new();
    if let Some(path) = std::env::var_os("ONLYOFFICE_X2T_PATH") {
        let path = PathBuf::from(path);
        if path.is_file() {
            let parent = path.parent().unwrap_or(Path::new(".")).to_path_buf();
            return Ok((path, parent));
        }
        candidates.push(path);
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            candidates.push(parent.join("onlyoffice"));
            candidates.push(parent.to_path_buf());
        }
    }
    candidates.push(PathBuf::from("onlyoffice"));

    let mut searched = Vec::new();
    for candidate in candidates {
        let directories = [
            candidate.clone(),
            candidate.join("server").join("FileConverter").join("bin"),
            candidate.join("FileConverter").join("bin"),
            candidate.join("bin"),
        ];
        for directory in directories {
            searched.push(directory.display().to_string());
            if let Some(x2t) = find_x2t_in(&directory) {
                return Ok((x2t, directory));
            }
        }
    }

    Err(format!(
        "ONLYOFFICE x2t was not found. Set ONLYOFFICE_X2T_PATH or provide the bundled onlyoffice runtime. Searched: {}",
        searched.join(", ")
    ))
}

fn first_existing_directory(candidates: impl IntoIterator<Item = PathBuf>) -> Option<PathBuf> {
    candidates.into_iter().find(|path| path.is_dir())
}

fn font_directory(runtime: &Path) -> Option<PathBuf> {
    first_existing_directory([
        runtime.join("core-fonts"),
        runtime.join("fonts"),
        runtime.join(Path::new("..")).join("core-fonts"),
        runtime
            .join(Path::new(".."))
            .join(Path::new(".."))
            .join("core-fonts"),
        runtime
            .join(Path::new(".."))
            .join(Path::new(".."))
            .join(Path::new(".."))
            .join("core-fonts"),
    ])
}

fn theme_directory(runtime: &Path) -> Option<PathBuf> {
    first_existing_directory([
        runtime.join("sdkjs").join("slide").join("themes"),
        runtime
            .join(Path::new(".."))
            .join("sdkjs")
            .join("slide")
            .join("themes"),
        runtime
            .join(Path::new(".."))
            .join(Path::new(".."))
            .join("sdkjs")
            .join("slide")
            .join("themes"),
        runtime
            .join(Path::new(".."))
            .join(Path::new(".."))
            .join(Path::new(".."))
            .join("sdkjs")
            .join("slide")
            .join("themes"),
    ])
}

fn xml_escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

fn conversion_directory() -> Result<PathBuf, String> {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| format!("clock error: {error}"))?
        .as_nanos();
    let directory = std::env::temp_dir()
        .join("Inf-Dir")
        .join("onlyoffice-view")
        .join(format!("{}-{timestamp}", std::process::id()));
    fs::create_dir_all(&directory)
        .map_err(|error| format!("failed to create conversion directory: {error}"))?;
    Ok(directory)
}

fn create_params(source: &Path, output: &Path, directory: &Path, runtime: &Path) -> String {
    let mut xml = format!(
        "<?xml version=\"1.0\" encoding=\"utf-8\"?><TaskQueueDataConvert xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\"><m_sFileFrom>{}</m_sFileFrom><m_sFileTo>{}</m_sFileTo><m_nFormatTo>{PDF_FORMAT_CODE}</m_nFormatTo><m_sTempDir>{}</m_sTempDir>",
        xml_escape(&source.to_string_lossy()),
        xml_escape(&output.to_string_lossy()),
        xml_escape(&directory.to_string_lossy()),
    );
    if let Some(fonts) = font_directory(runtime) {
        xml.push_str(&format!(
            "<m_sFontDir>{}</m_sFontDir>",
            xml_escape(&fonts.to_string_lossy())
        ));
    }
    if let Some(themes) = theme_directory(runtime) {
        xml.push_str(&format!(
            "<m_sThemeDir>{}</m_sThemeDir>",
            xml_escape(&themes.to_string_lossy())
        ));
    }
    xml.push_str("<m_bIsNoBase64 xsi:nil=\"true\"/></TaskQueueDataConvert>");
    xml
}

fn terminate_process_tree(child: &mut Child) {
    #[cfg(windows)]
    {
        let _ = Command::new("taskkill")
            .args(["/PID", &child.id().to_string(), "/T", "/F"])
            .creation_flags(CREATE_NO_WINDOW)
            .status();
    }
    let _ = child.kill();
}

fn run_x2t(x2t: &Path, runtime: &Path, params: &Path) -> Result<(), String> {
    let mut command = Command::new(x2t);
    command
        .arg(params)
        .current_dir(runtime)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    #[cfg(windows)]
    command.creation_flags(CREATE_NO_WINDOW);

    let mut child = command
        .spawn()
        .map_err(|error| format!("failed to start x2t: {error}"))?;
    let start = SystemTime::now();
    loop {
        if let Some(status) = child
            .try_wait()
            .map_err(|error| format!("failed waiting for x2t: {error}"))?
        {
            if status.success() {
                return Ok(());
            }
            return Err(format!("x2t exited with status {status}"));
        }
        if start.elapsed().unwrap_or_default() > X2T_TIMEOUT {
            terminate_process_tree(&mut child);
            return Err(format!(
                "x2t timed out after {} seconds",
                X2T_TIMEOUT.as_secs()
            ));
        }
        thread::sleep(Duration::from_millis(100));
    }
}

fn convert_to_pdf(source: &Path) -> Result<Conversion, String> {
    let (x2t, runtime) = resolve_x2t()?;
    let directory = conversion_directory()?;
    let output = directory.join("converted.pdf");
    let params_path = directory.join("params.xml");
    let params = create_params(source, &output, &directory, &runtime);
    if let Err(error) = fs::write(&params_path, params.as_bytes()) {
        let _ = fs::remove_dir_all(&directory);
        return Err(format!("failed to write x2t parameters: {error}"));
    }
    if let Err(error) = run_x2t(&x2t, &runtime, &params_path) {
        let _ = fs::remove_dir_all(&directory);
        return Err(error);
    }
    if !output.is_file() {
        let _ = fs::remove_dir_all(&directory);
        return Err(format!(
            "x2t completed without creating {}",
            output.display()
        ));
    }
    Ok(Conversion {
        directory,
        pdf: output,
    })
}

fn resolve_web_root() -> Option<PathBuf> {
    let mut candidates = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            candidates.push(parent.join(WEB_DIR_NAME));
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
        .join("onlyoffice-view")
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
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("woff") => "font/woff",
        Some("woff2") => "font/woff2",
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
    target_pdf: &Path,
) -> Response<Cow<'static, [u8]>> {
    let path = request.uri().path();
    if path == "/file" {
        return match fs::read(target_pdf) {
            Ok(bytes) => response(StatusCode::OK, "application/pdf", bytes),
            Err(error) => response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                format!("Could not read converted PDF\n{error}").into_bytes(),
            ),
        };
    }

    let relative = if path.is_empty() || path == "/" {
        "web/viewer.html"
    } else {
        path
    };
    match safe_join(web_root, relative) {
        Some(target) => match fs::read(&target) {
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
    conversion: Conversion,
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
            .with_title(format!("{file_name} - ONLYOFFICE Viewer"))
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
                eprintln!("[onlyoffice-view] failed to create window: {error}");
                event_loop.exit();
                return;
            }
        };

        let web_root = self.web_root.clone();
        let target_pdf = self.conversion.pdf.clone();
        let start_url = format!("{SCHEME}://{HOST}/web/viewer.html?file=../file");
        let webview = match WebViewBuilder::new_with_web_context(&mut self.web_context)
            .with_custom_protocol(SCHEME.into(), move |_id, request| {
                handle_request(request, &web_root, &target_pdf)
            })
            .with_navigation_handler(|url| url.contains(HOST))
            .with_url(&start_url)
            .build(&window)
        {
            Ok(webview) => webview,
            Err(error) => {
                eprintln!("[onlyoffice-view] failed to initialize WebView2: {error}");
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
            eprintln!("[onlyoffice-view] {error}");
            std::process::exit(1);
        }
    };
    let web_root = match resolve_web_root() {
        Some(root) => root,
        None => {
            eprintln!("[onlyoffice-view] could not find {WEB_DIR_NAME} beside the executable");
            std::process::exit(1);
        }
    };
    let conversion = match convert_to_pdf(&args.file) {
        Ok(conversion) => conversion,
        Err(error) => {
            eprintln!("[onlyoffice-view] conversion failed: {error}");
            std::process::exit(1);
        }
    };
    let event_loop = match EventLoop::new() {
        Ok(event_loop) => event_loop,
        Err(error) => {
            eprintln!("[onlyoffice-view] failed to create event loop: {error}");
            let _ = fs::remove_dir_all(&conversion.directory);
            std::process::exit(1);
        }
    };
    let mut app = App {
        args,
        conversion,
        web_root,
        window: None,
        webview: None,
        web_context: WebContext::new(Some(webview_data_directory())),
    };
    let _ = event_loop.run_app(&mut app);
    let _ = fs::remove_dir_all(&app.conversion.directory);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn supported_formats_exclude_excel() {
        assert!(is_supported_file(Path::new("report.docx")));
        assert!(is_supported_file(Path::new("slides.PPTX")));
        assert!(is_supported_file(Path::new("diagram.vsdx")));
        assert!(is_supported_file(Path::new("notes.odt")));
        assert!(!is_supported_file(Path::new("book.xlsx")));
        assert!(!is_supported_file(Path::new("book.xlsm")));
    }

    #[test]
    fn xml_paths_are_escaped() {
        let xml = create_params(
            Path::new(r"C:\docs\a&b<draft>.docx"),
            Path::new(r"C:\temp\out.pdf"),
            Path::new(r"C:\temp\work"),
            Path::new(r"C:\missing-runtime"),
        );
        assert!(xml.contains("a&amp;b&lt;draft&gt;.docx"));
        assert!(!xml.contains("a&b<draft>.docx"));
        assert!(xml.contains("<m_nFormatTo>513</m_nFormatTo>"));
    }

    #[test]
    fn safe_join_rejects_windows_escape_segments() {
        let root = Path::new(r"C:\viewer\web");
        assert!(safe_join(root, "/web/viewer.html").is_some());
        assert!(safe_join(root, "/../secret.txt").is_none());
        assert!(safe_join(root, "/C:/secret.txt").is_none());
        assert!(safe_join(root, "/folder\\secret.txt").is_none());
    }
}
