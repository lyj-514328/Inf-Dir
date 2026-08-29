use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, RwLock};

use dpi::{LogicalSize, PhysicalPosition, PhysicalSize};
use http::{Request, StatusCode};
use serde_json::Value;
use viewer_web_shell::{response, safe_join};
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};
use winit::application::ApplicationHandler;
use winit::event::{ElementState, KeyEvent, WindowEvent};
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::window::{Window, WindowId};
use wry::{WebContext, WebViewBuilder};

const SCHEME: &str = "project-view";
const HOST: &str = "localhost";
const WEB_DIR_NAME: &str = "project-view-web";

#[derive(Debug)]
struct Args {
    file: PathBuf,
    window_placement: Option<WindowPlacement>,
}

#[derive(Clone, Debug)]
enum LoadState {
    Loading,
    Ready(Vec<u8>),
    Error(String),
}

type SharedLoadState = Arc<RwLock<LoadState>>;

#[derive(Clone, Debug)]
struct ParserCommand {
    program: PathBuf,
    prefix_args: Vec<String>,
}

fn parse_args() -> Result<Args, String> {
    parse_args_from(std::env::args().skip(1))
}

fn parse_args_from(args: impl IntoIterator<Item = String>) -> Result<Args, String> {
    let mut file = None;
    let mut window_placement = None;
    let mut iterator = args.into_iter();
    while let Some(argument) = iterator.next() {
        match argument.as_str() {
            WINDOW_PLACEMENT_ARGUMENT => {
                if window_placement.is_some() {
                    return Err(format!("duplicate option: {WINDOW_PLACEMENT_ARGUMENT}"));
                }
                let value = iterator
                    .next()
                    .ok_or_else(|| format!("{WINDOW_PLACEMENT_ARGUMENT} requires a JSON value"))?;
                window_placement = Some(WindowPlacement::from_json(&value)?);
            }
            _ if argument.starts_with('-') && argument != "-" => {
                return Err(format!("unknown option: {argument}"));
            }
            _ => {
                if file.is_some() {
                    return Err(format!("unexpected argument: {argument}"));
                }
                file = Some(PathBuf::from(argument));
            }
        }
    }
    let file = file.ok_or_else(|| {
        format!("Usage: project-view.exe <FILE> [{WINDOW_PLACEMENT_ARGUMENT} <JSON>]")
    })?;
    if !file.is_file() {
        return Err(format!("file does not exist: {}", file.display()));
    }
    Ok(Args {
        file: file.canonicalize().map_err(|error| error.to_string())?,
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
    candidates.push(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../web"));
    candidates
        .into_iter()
        .find(|root| root.join("index.html").is_file())
}

fn webview_data_directory() -> PathBuf {
    std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join("Inf-Dir")
        .join("WebView2")
        .join("project-view")
}

fn resolve_parser_command() -> Result<ParserCommand, String> {
    let mut roots = Vec::new();
    if let Ok(executable) = std::env::current_exe() {
        if let Some(directory) = executable.parent() {
            roots.push(directory.to_path_buf());
        }
    }
    roots.push(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(".."));
    roots.push(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../backend"));

    for root in &roots {
        let executable = root.join("project-parser").join("project-parser.exe");
        if executable.is_file() {
            return Ok(ParserCommand {
                program: executable,
                prefix_args: Vec::new(),
            });
        }
        let jar = root
            .join("backend")
            .join("target")
            .join("project-parser-0.1.0.jar");
        if jar.is_file() {
            return Ok(ParserCommand {
                program: java_executable(),
                prefix_args: vec!["-jar".to_owned(), jar.to_string_lossy().into_owned()],
            });
        }
        let jar = root.join("target").join("project-parser-0.1.0.jar");
        if jar.is_file() {
            return Ok(ParserCommand {
                program: java_executable(),
                prefix_args: vec!["-jar".to_owned(), jar.to_string_lossy().into_owned()],
            });
        }
    }
    Err("project-parser executable was not found beside project-view.exe".to_owned())
}

fn java_executable() -> PathBuf {
    if let Some(java_home) = std::env::var_os("JAVA_HOME") {
        let candidate = PathBuf::from(java_home).join("bin").join("java.exe");
        if candidate.is_file() {
            return candidate;
        }
    }
    PathBuf::from("java")
}

fn start_parser(file: PathBuf, state: SharedLoadState) {
    std::thread::spawn(move || {
        let command = match resolve_parser_command() {
            Ok(command) => command,
            Err(error) => {
                set_state(&state, LoadState::Error(error));
                return;
            }
        };
        let mut process = Command::new(&command.program);
        process.args(&command.prefix_args).arg("--input").arg(&file);
        let output = match process.output() {
            Ok(output) => output,
            Err(error) => {
                set_state(
                    &state,
                    LoadState::Error(format!("failed to start project parser: {error}")),
                );
                return;
            }
        };
        if !output.status.success() {
            let detail = String::from_utf8_lossy(&output.stderr).trim().to_owned();
            let message = if detail.is_empty() {
                format!("project parser exited with {}", output.status)
            } else {
                detail
            };
            set_state(&state, LoadState::Error(message));
            return;
        }
        if serde_json::from_slice::<Value>(&output.stdout).is_err() {
            set_state(
                &state,
                LoadState::Error("project parser returned invalid JSON".to_owned()),
            );
            return;
        }
        set_state(&state, LoadState::Ready(output.stdout));
    });
}

fn set_state(state: &SharedLoadState, next: LoadState) {
    if let Ok(mut current) = state.write() {
        *current = next;
    }
}

fn json_response(status: StatusCode, body: String) -> viewer_web_shell::WebResponse {
    response(status, "application/json; charset=utf-8", body.into_bytes())
}

fn static_response(web_root: &Path, request_path: &str) -> viewer_web_shell::WebResponse {
    let relative = if request_path.is_empty() || request_path == "/" {
        "index.html"
    } else {
        request_path
    };
    match safe_join(web_root, relative) {
        Some(target) => match std::fs::read(&target) {
            Ok(bytes) => response(StatusCode::OK, viewer_web_shell::mime_for(&target), bytes),
            Err(_) => response(
                StatusCode::NOT_FOUND,
                "text/plain; charset=utf-8",
                b"not found".to_vec(),
            ),
        },
        None => response(
            StatusCode::BAD_REQUEST,
            "text/plain; charset=utf-8",
            b"bad request".to_vec(),
        ),
    }
}

fn handle_request(
    request: Request<Vec<u8>>,
    web_root: &Path,
    state: &SharedLoadState,
) -> viewer_web_shell::WebResponse {
    if request.uri().path() == "/api/project" {
        return match state.read().map(|value| value.clone()) {
            Ok(LoadState::Loading) => {
                json_response(StatusCode::ACCEPTED, r#"{"status":"loading"}"#.to_owned())
            }
            Ok(LoadState::Ready(bytes)) => {
                response(StatusCode::OK, "application/json; charset=utf-8", bytes)
            }
            Ok(LoadState::Error(error)) => json_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!(r#"{{"status":"error","message":{}}}"#, json_quote(&error)),
            ),
            Err(_) => json_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                r#"{"status":"error","message":"state unavailable"}"#.to_owned(),
            ),
        };
    }
    static_response(web_root, request.uri().path())
}

fn json_quote(value: &str) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "\"unknown error\"".to_owned())
}

struct App {
    args: Args,
    web_root: PathBuf,
    state: SharedLoadState,
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
            .unwrap_or_else(|| "Project".to_owned());
        let mut attributes = Window::default_attributes()
            .with_title(format!("{file_name} - Project View"))
            .with_min_inner_size(LogicalSize::new(760u32, 480u32))
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
            attributes = attributes.with_inner_size(LogicalSize::new(1280u32, 820u32));
        }
        let window = match event_loop.create_window(attributes) {
            Ok(window) => window,
            Err(error) => {
                eprintln!("[project-view] failed to create window: {error}");
                event_loop.exit();
                return;
            }
        };
        let state = self.state.clone();
        let web_root = self.web_root.clone();
        let start_url = format!("{SCHEME}://{HOST}/index.html");
        let allowed_origins = [
            format!("{SCHEME}://{HOST}/"),
            format!("http://{SCHEME}.localhost/"),
        ];
        let webview = match WebViewBuilder::new_with_web_context(&mut self.web_context)
            .with_custom_protocol(SCHEME.into(), move |_id, request| {
                handle_request(request, &web_root, &state)
            })
            .with_navigation_handler(move |url| {
                allowed_origins.iter().any(|origin| url.starts_with(origin))
            })
            .with_url(&start_url)
            .build(&window)
        {
            Ok(webview) => webview,
            Err(error) => {
                eprintln!("[project-view] failed to initialize WebView2: {error}");
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
            eprintln!("[project-view] {error}");
            std::process::exit(2);
        }
    };
    let web_root = match resolve_web_root() {
        Some(root) => root,
        None => {
            eprintln!("[project-view] could not find {WEB_DIR_NAME} beside the executable");
            std::process::exit(1);
        }
    };
    let state = Arc::new(RwLock::new(LoadState::Loading));
    start_parser(args.file.clone(), state.clone());
    let event_loop = match EventLoop::new() {
        Ok(event_loop) => event_loop,
        Err(error) => {
            eprintln!("[project-view] failed to create event loop: {error}");
            std::process::exit(1);
        }
    };
    let mut app = App {
        args,
        web_root,
        state,
        window: None,
        webview: None,
        web_context: WebContext::new(Some(webview_data_directory())),
    };
    let _ = event_loop.run_app(&mut app);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parser_state_starts_loading() {
        let state = Arc::new(RwLock::new(LoadState::Loading));
        assert!(matches!(*state.read().unwrap(), LoadState::Loading));
    }

    #[test]
    fn quote_escapes_json_control_characters() {
        assert_eq!(json_quote("a\"b\n"), "\"a\\\"b\\n\"");
    }

    #[test]
    fn static_root_is_resolved_from_manifest() {
        assert!(PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../web")
            .ends_with("web"));
    }
}
