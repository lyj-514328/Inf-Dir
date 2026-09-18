//! Inf-Dir font Quick View host.
//!
//! The font itself is never parsed (except the DFONT container): the file is
//! copied into a private temporary directory and loaded by WebView2 through a
//! CSS `@font-face` rule, so the system DirectWrite engine renders it. The
//! temporary directory is removed when the window closes.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use http::{Request, StatusCode};
use viewer_web_shell::{mime_for, response, safe_join, WebViewConfig};
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};

mod dfont;

const SCHEME: &str = "http";
const HOST: &str = "font-view.local";
const SUPPORTED_EXTENSIONS: [&str; 6] = ["ttf", "otf", "woff", "woff2", "ttc", "dfont"];

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
        format!(
            "usage: font-view.exe <FONT_FILE> [{WINDOW_PLACEMENT_ARGUMENT} <JSON>], extensions: {}",
            SUPPORTED_EXTENSIONS.join(", ")
        )
    })?;
    if !file.is_file() {
        return Err(format!("file does not exist: {}", file.display()));
    }
    if !is_supported_extension(&file) {
        return Err(format!("unsupported font extension: {}", file.display()));
    }

    Ok(Args {
        file,
        window_placement,
    })
}

fn is_supported_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|value| value.to_str())
        .is_some_and(|extension| {
            SUPPORTED_EXTENSIONS
                .iter()
                .any(|candidate| candidate.eq_ignore_ascii_case(extension))
        })
}

/// Builds the private staging directory: `source.<ext>` plus `index.html`.
/// DFONT is unwrapped to plain TTF first; every other format is copied.
fn prepare(source: &Path) -> Result<PathBuf, String> {
    let display_extension = source
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase();
    let web_extension = if display_extension == "dfont" {
        "ttf"
    } else {
        display_extension.as_str()
    };
    let font_file = format!("source.{web_extension}");

    let temp_root = std::env::temp_dir()
        .join("Inf-Dir")
        .join("font-view");
    fs::create_dir_all(&temp_root).map_err(|error| error.to_string())?;
    let directory = temp_root.join(format!(
        "{}-{:?}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|value| value.subsec_nanos())
            .unwrap_or_default()
    ));
    fs::create_dir_all(&directory).map_err(|error| error.to_string())?;

    let prepared_font = directory.join(&font_file);
    if display_extension == "dfont" {
        dfont::extract_dfont(source, &prepared_font)?;
    } else {
        fs::copy(source, &prepared_font).map_err(|error| error.to_string())?;
    }
    let html = build_html(
        &font_file,
        format_hint(web_extension),
        &html_escape(
            source
                .file_name()
                .map(|value| value.to_string_lossy().into_owned())
                .unwrap_or_else(|| source.display().to_string())
                .as_str(),
        ),
        display_extension.to_ascii_uppercase().as_str(),
        &file_size_label(source),
    );
    fs::write(directory.join("index.html"), html).map_err(|error| error.to_string())?;
    Ok(directory)
}

fn format_hint(web_extension: &str) -> &'static str {
    match web_extension {
        "woff2" => " format('woff2')",
        "woff" => " format('woff')",
        "otf" => " format('opentype')",
        "ttf" | "ttc" => " format('truetype')",
        _ => "",
    }
}

fn file_size_label(path: &Path) -> String {
    let bytes = fs::metadata(path).map(|value| value.len()).unwrap_or_default();
    const KB: f64 = 1024.0;
    const MB: f64 = 1024.0 * 1024.0;
    match bytes as f64 {
        value if value < KB => format!("{bytes} B"),
        value if value < MB => format!("{:.1} KB", value / KB),
        value => format!("{:.1} MB", value / MB),
    }
}

fn html_escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

fn build_html(font_file: &str, format_hint: &str, name: &str, extension: &str, size: &str) -> String {
    let template = r#"<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; font-src 'self'">
<style>
@font-face{font-family:Preview;src:url('./@FONT_FILE@')@FORMAT_HINT@;font-display:block}
*{box-sizing:border-box}body{margin:0;background:#f7f8fa;color:#202124;font-family:Segoe UI,sans-serif}
header{height:58px;padding:9px 18px;border-bottom:1px solid #dfe1e5;background:#fff;display:flex;align-items:center;gap:18px}
.meta{min-width:0;flex:1}.name{font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.sub{font-size:12px;color:#687078;margin-top:2px}
label{display:flex;align-items:center;gap:8px;font-size:13px;color:#4b535b}input[type=range]{width:150px}
main{padding:28px clamp(24px,6vw,84px)}#error{display:none;padding:14px;background:#fff1f0;color:#a61d24;border:1px solid #ffccc7}
.sample{font-family:Preview,Segoe UI,sans-serif;outline:none;line-height:1.35;overflow-wrap:anywhere;border-bottom:1px solid #e2e5e9;padding:22px 0}
#hero{font-size:72px}.row{font-size:34px}.small{font-size:20px;line-height:1.6}
</style></head><body><header><div class="meta"><div class="name">@NAME@</div><div class="sub">@EXT@ · @SIZE@</div></div>
<label>字号 <input id="size" type="range" min="24" max="128" value="72"><output id="value">72 px</output></label></header>
<main><div id="error">字体无法由系统的 WebView2 字体引擎加载。</div>
<div id="hero" class="sample" contenteditable="true" spellcheck="false">Inf-Dir 文件管理器</div>
<div class="sample row" contenteditable="true" spellcheck="false">天地玄黄 宇宙洪荒 · 0123456789</div>
<div class="sample row" contenteditable="true" spellcheck="false">The quick brown fox jumps over the lazy dog.</div>
<div class="sample small" contenteditable="true" spellcheck="false">ABCDEFGHIJKLMNOPQRSTUVWXYZ<br>abcdefghijklmnopqrstuvwxyz<br>!@#$%^&amp;*() [] {} &lt;&gt; / \ + =</div></main>
<script>
const slider=document.getElementById('size'),hero=document.getElementById('hero'),value=document.getElementById('value');
slider.addEventListener('input',()=>{hero.style.fontSize=slider.value+'px';value.textContent=slider.value+' px'});
document.fonts.load('32px Preview').then(fonts=>{if(!fonts.length)document.getElementById('error').style.display='block'}).catch(()=>document.getElementById('error').style.display='block');
</script></body></html>
"#;
    template
        .replace("@FONT_FILE@", font_file)
        .replace("@FORMAT_HINT@", format_hint)
        .replace("@NAME@", name)
        .replace("@EXT@", extension)
        .replace("@SIZE@", size)
}

fn handle_request(req: Request<Vec<u8>>, root: &Path) -> viewer_web_shell::WebResponse {
    let relative = if req.uri().path().is_empty() || req.uri().path() == "/" {
        "index.html"
    } else {
        req.uri().path()
    };
    match safe_join(root, relative) {
        Some(target) => match fs::read(&target) {
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

fn main() {
    let args = match parse_args() {
        Ok(args) => args,
        Err(error) => {
            eprintln!("[font-view] {error}");
            std::process::exit(1);
        }
    };
    let source = match args.file.canonicalize() {
        Ok(path) => path,
        Err(error) => {
            eprintln!("[font-view] failed to resolve file: {error}");
            std::process::exit(1);
        }
    };
    let name = source
        .file_name()
        .map(|value| value.to_string_lossy().into_owned())
        .unwrap_or_else(|| source.display().to_string());
    let staging = match prepare(&source) {
        Ok(directory) => directory,
        Err(error) => {
            eprintln!("[font-view] {error}");
            std::process::exit(1);
        }
    };
    let root = staging.clone();
    let router = Arc::new(move |request| handle_request(request, &root));
    let config = WebViewConfig {
        title: format!("{name} - 字体查看器"),
        host: HOST.to_owned(),
        scheme: SCHEME.to_owned(),
        start_url: format!("{SCHEME}://{HOST}/index.html"),
        window_placement: args.window_placement,
        request_handler: router,
        ipc_handler: None,
    };
    let result = viewer_web_shell::run(config);
    let _ = fs::remove_dir_all(&staging);
    if let Err(error) = result {
        eprintln!("[font-view] {error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn font_fixture(extension: &str) -> PathBuf {
        static COUNTER: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let path = std::env::temp_dir().join(format!(
            "inf-dir-font-view-arg-test-{}-{}.{}",
            std::process::id(),
            COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed),
            extension
        ));
        let mut file = fs::File::create(&path).unwrap();
        file.write_all(b"dummy").unwrap();
        path
    }

    #[test]
    fn parses_window_placement_before_or_after_file() {
        let fixture = font_fixture("ttf");
        let placement_json =
            r#"{"version":2,"x":1024,"y":0,"clientWidth":1008,"clientHeight":1113,"maximized":false}"#;
        for arguments in [
            vec![
                fixture.to_string_lossy().into_owned(),
                WINDOW_PLACEMENT_ARGUMENT.to_owned(),
                placement_json.to_owned(),
            ],
            vec![
                WINDOW_PLACEMENT_ARGUMENT.to_owned(),
                placement_json.to_owned(),
                fixture.to_string_lossy().into_owned(),
            ],
        ] {
            let args = parse_args_from(arguments).unwrap();
            assert_eq!(args.window_placement.unwrap().x, 1024);
        }
        fs::remove_file(&fixture).unwrap();
    }

    #[test]
    fn rejects_unknown_options_and_unsupported_extensions() {
        assert!(parse_args_from(vec!["--unknown".to_owned()]).is_err());
        let fixture = font_fixture("ttf");
        assert!(parse_args_from(vec![
            fixture.to_string_lossy().into_owned(),
            fixture.to_string_lossy().into_owned(),
        ])
        .is_err());
        fs::remove_file(&fixture).unwrap();
        let exe = font_fixture("exe");
        assert!(parse_args_from(vec![exe.to_string_lossy().into_owned()]).is_err());
        fs::remove_file(&exe).unwrap();
    }

    #[test]
    fn staging_directory_contains_font_and_preview_page() {
        let fixture = font_fixture("woff2");
        let staging = prepare(&fixture).unwrap();
        assert!(staging.join("index.html").is_file());
        assert!(staging.join("source.woff2").is_file());
        let html = fs::read_to_string(staging.join("index.html")).unwrap();
        assert!(html.contains("url('./source.woff2') format('woff2')"));
        let _ = fs::remove_dir_all(&staging);
        fs::remove_file(&fixture).unwrap();
    }

    #[test]
    fn dfont_stage_uses_extracted_ttf_name() {
        let path = std::env::temp_dir().join(format!(
            "inf-dir-font-view-dfont-test-{}.dfont",
            std::process::id()
        ));
        fs::write(&path, dfont::build_test_dfont(b"dummy-sfnt-payload")).unwrap();
        let staging = prepare(&path).unwrap();
        assert!(staging.join("source.ttf").is_file());
        assert_eq!(
            fs::read(staging.join("source.ttf")).unwrap(),
            b"dummy-sfnt-payload"
        );
        let html = fs::read_to_string(staging.join("index.html")).unwrap();
        assert!(html.contains("url('./source.ttf') format('truetype')"));
        assert!(html.contains("DFONT · "));
        let _ = fs::remove_dir_all(&staging);
        fs::remove_file(&path).unwrap();
    }
}
