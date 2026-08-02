use std::path::{Path, PathBuf};
use std::process::ExitCode;

use eframe::egui;
use egui::text::{LayoutJob, TextFormat};
use egui::{Color32, FontId};
use syntect::easy::HighlightLines;
use syntect::util::LinesWithEndings;
use two_face::re_exports::syntect;

const FONT_SIZE: f32 = 14.0;
const DEFAULT_WIDTH: f32 = 960.0;
const DEFAULT_HEIGHT: f32 = 720.0;

struct Args {
    file: PathBuf,
    width: f32,
    height: f32,
}

fn usage() -> String {
    "Usage: text-view <FILE> [--width W] [--height H]".to_string()
}

fn parse_args() -> Result<Args, String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut file: Option<String> = None;
    let mut width = DEFAULT_WIDTH;
    let mut height = DEFAULT_HEIGHT;

    let mut i = 0;
    while i < args.len() {
        let arg = args[i].clone();
        match arg.as_str() {
            "--width" | "-w" => {
                i += 1;
                let v = args
                    .get(i)
                    .ok_or_else(|| format!("--width requires a value\n{}", usage()))?;
                width = v.parse::<f32>().map_err(|_| format!("invalid width: {v}"))?;
            }
            "--height" | "-h" => {
                i += 1;
                let v = args
                    .get(i)
                    .ok_or_else(|| format!("--height requires a value\n{}", usage()))?;
                height = v.parse::<f32>().map_err(|_| format!("invalid height: {v}"))?;
            }
            _ if arg.starts_with('-') && arg != "-" => {
                return Err(format!("unknown flag: {arg}\n{}", usage()));
            }
            _ => {
                if file.is_some() {
                    return Err(format!("unexpected argument: {arg}\n{}", usage()));
                }
                file = Some(arg);
            }
        }
        i += 1;
    }

    let file = file.ok_or_else(usage)?;
    if !width.is_finite() || width <= 0.0 || !height.is_finite() || height <= 0.0 {
        return Err(format!("invalid window size\n{}", usage()));
    }
    Ok(Args {
        file: PathBuf::from(file),
        width,
        height,
    })
}

struct TextViewer {
    job: LayoutJob,
    bg: Color32,
}

impl TextViewer {
    fn new(text: &str, path: &Path) -> Self {
        let syntax_set = two_face::syntax::extra_newlines();
        let theme_set = two_face::theme::extra();
        let theme = &theme_set[two_face::theme::EmbeddedThemeName::Nord];

        let syntax = path
            .extension()
            .and_then(|ext| {
                let ext = ext.to_string_lossy();
                syntax_set.find_syntax_by_extension(&ext)
            })
            .or_else(|| syntax_set.find_syntax_by_path(&path.to_string_lossy()))
            .unwrap_or_else(|| syntax_set.find_syntax_plain_text());

        let mut highlighter = HighlightLines::new(syntax, theme);

        let line_count = text.lines().count().max(1);
        let gutter_width = line_count.to_string().len();

        let bg = theme
            .settings
            .background
            .map(|c| Color32::from_rgb(c.r, c.g, c.b))
            .unwrap_or(Color32::from_rgb(0x2e, 0x34, 0x40));

        let mono = FontId::monospace(FONT_SIZE);
        let gutter_fmt = TextFormat {
            font_id: mono.clone(),
            color: Color32::from_gray(110),
            ..Default::default()
        };

        let mut job = LayoutJob::default();
        for (idx, line) in LinesWithEndings::from(text).enumerate() {
            job.append(
                &format!("{:>w$} \u{2502} ", idx + 1, w = gutter_width),
                0.0,
                gutter_fmt.clone(),
            );
            let ranges = highlighter.highlight_line(line, &syntax_set).unwrap_or_default();
            for (style, span) in ranges {
                let fg = style.foreground;
                let fmt = TextFormat {
                    font_id: mono.clone(),
                    color: Color32::from_rgb(fg.r, fg.g, fg.b),
                    ..Default::default()
                };
                job.append(span, 0.0, fmt);
            }
        }

        Self { job, bg }
    }
}

impl eframe::App for TextViewer {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        if ctx.input(|i| i.key_pressed(egui::Key::Escape)) {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }

        let bg = self.bg;
        egui::CentralPanel::default()
            .frame(egui::Frame::default().fill(bg).inner_margin(6.0))
            .show(ctx, |ui| {
                egui::ScrollArea::both()
                    .auto_shrink([false, false])
                    .show(ui, |ui| {
                        ui.label(self.job.clone());
                    });
            });
    }
}

fn main() -> ExitCode {
    let args = match parse_args() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("{e}");
            return ExitCode::from(1);
        }
    };

    if !args.file.exists() {
        eprintln!("error: file does not exist: {}", args.file.display());
        return ExitCode::from(1);
    }

    let bytes = match std::fs::read(&args.file) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("error: cannot read {}: {e}", args.file.display());
            return ExitCode::from(1);
        }
    };
    let text = String::from_utf8_lossy(&bytes).into_owned();
    let title = format!("text-view \u{2014} {}", args.file.display());

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([args.width, args.height])
            .with_title(&title),
        ..Default::default()
    };

    let viewer = TextViewer::new(&text, &args.file);
    match eframe::run_native(
        "text-view",
        options,
        Box::new(move |cc| {
            cc.egui_ctx.set_visuals(egui::Visuals::dark());

            // CJK fallback: load a system Chinese font so CJK glyphs render
            let mut fonts = egui::FontDefinitions::default();
            let candidates = [
                r"C:\Windows\Fonts\msyh.ttc",   // Microsoft YaHei
                r"C:\Windows\Fonts\simhei.ttf",  // SimHei
                r"C:\Windows\Fonts\simsun.ttc",  // SimSun
            ];
            for path in candidates {
                if let Ok(data) = std::fs::read(path) {
                    fonts.font_data.insert("cjk".to_owned(), egui::FontData::from_owned(data));
                    fonts.families
                        .entry(egui::FontFamily::Monospace)
                        .or_default()
                        .push("cjk".to_owned());
                    break;
                }
            }
            cc.egui_ctx.set_fonts(fonts);

            Ok(Box::new(viewer))
        }),
    ) {
        Ok(_) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::from(1)
        }
    }
}
