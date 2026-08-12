use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::Arc;

use eframe::egui;
use egui::text::{LayoutJob, TextFormat};
use egui::{Color32, FontId};
use syntect::easy::HighlightLines;
use syntect::util::LinesWithEndings;
use two_face::re_exports::syntect;

const FONT_SIZE: f32 = 14.0;
const LINE_HEIGHT: f32 = 20.0;
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
                width = v
                    .parse::<f32>()
                    .map_err(|_| format!("invalid width: {v}"))?;
            }
            "--height" | "-h" => {
                i += 1;
                let v = args
                    .get(i)
                    .ok_or_else(|| format!("--height requires a value\n{}", usage()))?;
                height = v
                    .parse::<f32>()
                    .map_err(|_| format!("invalid height: {v}"))?;
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
    document_job: LayoutJob,
    line_jobs: Vec<LayoutJob>,
    gutter_digits: usize,
    bg: Color32,
    word_wrap: bool,
    wrapped_layout: Option<WrappedLayout>,
}

struct WrappedLayout {
    body_width: f32,
    galleys: Vec<Arc<egui::Galley>>,
    row_offsets: Vec<f32>,
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

        let mut lines: Vec<&str> = LinesWithEndings::from(text).collect();
        if lines.is_empty() {
            lines.push("");
        }
        let gutter_digits = lines.len().to_string().len();

        let bg = theme
            .settings
            .background
            .map(|c| Color32::from_rgb(c.r, c.g, c.b))
            .unwrap_or(Color32::from_rgb(0x2e, 0x34, 0x40));

        let mono = FontId::monospace(FONT_SIZE);
        let gutter_fmt = TextFormat {
            font_id: mono.clone(),
            color: Color32::from_gray(110),
            line_height: Some(LINE_HEIGHT),
            ..Default::default()
        };
        let plain_fmt = TextFormat {
            font_id: mono.clone(),
            color: theme
                .settings
                .foreground
                .map(|c| Color32::from_rgb(c.r, c.g, c.b))
                .unwrap_or(Color32::from_gray(216)),
            line_height: Some(LINE_HEIGHT),
            ..Default::default()
        };

        let mut document_job = LayoutJob::default();
        let mut line_jobs = Vec::with_capacity(lines.len());
        for (idx, line) in lines.into_iter().enumerate() {
            if idx > 0 {
                document_job.append("\n", 0.0, plain_fmt.clone());
            }
            document_job.append(
                &format!("{:>w$} \u{2502} ", idx + 1, w = gutter_digits),
                0.0,
                gutter_fmt.clone(),
            );

            let mut line_job = LayoutJob::default();
            line_job.wrap.break_anywhere = true;
            line_job.first_row_min_height = LINE_HEIGHT;

            let mut visible_bytes = line.trim_end_matches(['\r', '\n']).len();
            let ranges = highlighter
                .highlight_line(line, &syntax_set)
                .unwrap_or_default();
            for (style, span) in ranges {
                if visible_bytes == 0 {
                    break;
                }
                let visible_len = visible_bytes.min(span.len());
                let visible_span = &span[..visible_len];
                let fg = style.foreground;
                let fmt = TextFormat {
                    font_id: mono.clone(),
                    color: Color32::from_rgb(fg.r, fg.g, fg.b),
                    line_height: Some(LINE_HEIGHT),
                    ..Default::default()
                };
                document_job.append(visible_span, 0.0, fmt.clone());
                line_job.append(visible_span, 0.0, fmt);
                visible_bytes -= visible_len;
            }

            if line_job.text.is_empty() {
                line_job.append(" ", 0.0, plain_fmt.clone());
            }
            line_jobs.push(line_job);
        }

        Self {
            document_job,
            line_jobs,
            gutter_digits,
            bg,
            word_wrap: false,
            wrapped_layout: None,
        }
    }

    fn show_unwrapped(&self, ui: &mut egui::Ui) {
        egui::ScrollArea::both()
            .auto_shrink([false, false])
            .show(ui, |ui| {
                ui.add(egui::Label::new(self.document_job.clone()).extend());
            });
    }

    fn show_wrapped(&mut self, ui: &mut egui::Ui) {
        let gutter_sample = format!(
            "{:>w$} \u{2502} ",
            self.line_jobs.len(),
            w = self.gutter_digits
        );
        let gutter_width = ui.fonts(|fonts| {
            fonts
                .layout_no_wrap(
                    gutter_sample,
                    FontId::monospace(FONT_SIZE),
                    Color32::from_gray(110),
                )
                .size()
                .x
        });
        let body_width = (ui.available_width() - gutter_width).max(1.0);

        let layout_is_stale = self
            .wrapped_layout
            .as_ref()
            .map_or(true, |layout| (layout.body_width - body_width).abs() > 0.5);
        if layout_is_stale {
            let (galleys, row_offsets) = ui.fonts(|fonts| {
                let mut galleys = Vec::with_capacity(self.line_jobs.len());
                let mut row_offsets = Vec::with_capacity(self.line_jobs.len() + 1);
                row_offsets.push(0.0);

                for line_job in &self.line_jobs {
                    let mut job = line_job.clone();
                    job.wrap.max_width = body_width;
                    let galley = fonts.layout_job(job);
                    let next_offset = row_offsets.last().copied().unwrap_or_default()
                        + galley.size().y.max(LINE_HEIGHT);
                    galleys.push(galley);
                    row_offsets.push(next_offset);
                }
                (galleys, row_offsets)
            });
            self.wrapped_layout = Some(WrappedLayout {
                body_width,
                galleys,
                row_offsets,
            });
        }

        let layout = self
            .wrapped_layout
            .as_ref()
            .expect("wrapped layout was initialized");
        let total_height = layout.row_offsets.last().copied().unwrap_or(LINE_HEIGHT);

        egui::ScrollArea::vertical()
            .auto_shrink([false, false])
            .show_viewport(ui, |ui, viewport| {
                ui.set_height(total_height);
                let row_count = layout.galleys.len();
                let first_row = layout
                    .row_offsets
                    .partition_point(|offset| *offset <= viewport.min.y)
                    .saturating_sub(1)
                    .min(row_count.saturating_sub(1));
                let last_row = layout
                    .row_offsets
                    .partition_point(|offset| *offset < viewport.max.y)
                    .min(row_count);

                let origin = ui.min_rect().left_top();
                let body_x = origin.x + gutter_width;
                let painter = ui.painter();
                for idx in first_row..last_row {
                    let y = origin.y + layout.row_offsets[idx];
                    painter.text(
                        egui::pos2(body_x, y),
                        egui::Align2::RIGHT_TOP,
                        format!("{:>w$} \u{2502} ", idx + 1, w = self.gutter_digits),
                        FontId::monospace(FONT_SIZE),
                        Color32::from_gray(110),
                    );
                    painter.galley(
                        egui::pos2(body_x, y),
                        layout.galleys[idx].clone(),
                        Color32::WHITE,
                    );
                }
            });
    }
}

impl eframe::App for TextViewer {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        if ctx.input(|i| i.key_pressed(egui::Key::Escape)) {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }
        if ctx.input(|i| i.modifiers.alt && i.key_pressed(egui::Key::Z)) {
            self.word_wrap = !self.word_wrap;
        }

        let bg = self.bg;
        egui::TopBottomPanel::top("text_view_toolbar")
            .exact_height(36.0)
            .frame(
                egui::Frame::default()
                    .fill(bg)
                    .inner_margin(egui::Margin::symmetric(6.0, 4.0)),
            )
            .show(ctx, |ui| {
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    let response = ui
                        .selectable_label(self.word_wrap, "Wrap")
                        .on_hover_text("Toggle word wrap");
                    if response.clicked() {
                        self.word_wrap = !self.word_wrap;
                    }
                });
            });

        egui::CentralPanel::default()
            .frame(egui::Frame::default().fill(bg).inner_margin(6.0))
            .show(ctx, |ui| {
                if self.word_wrap {
                    self.show_wrapped(ui);
                } else {
                    self.show_unwrapped(ui);
                }
            });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn word_wrap_is_disabled_by_default() {
        let viewer = TextViewer::new("alpha\nbeta", Path::new("sample.txt"));

        assert!(!viewer.word_wrap);
    }

    #[test]
    fn wrapped_lines_exclude_line_endings() {
        let viewer = TextViewer::new("alpha\r\nbeta\n", Path::new("sample.txt"));

        assert_eq!(viewer.line_jobs.len(), 2);
        assert_eq!(viewer.line_jobs[0].text, "alpha");
        assert_eq!(viewer.line_jobs[1].text, "beta");
        assert!(viewer
            .line_jobs
            .iter()
            .all(|job| !job.text.contains(['\r', '\n'])));
    }

    #[test]
    fn empty_document_still_has_one_renderable_line() {
        let viewer = TextViewer::new("", Path::new("sample.txt"));

        assert_eq!(viewer.line_jobs.len(), 1);
        assert_eq!(viewer.gutter_digits, 1);
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
                r"C:\Windows\Fonts\simhei.ttf", // SimHei
                r"C:\Windows\Fonts\simsun.ttc", // SimSun
            ];
            for path in candidates {
                if let Ok(data) = std::fs::read(path) {
                    fonts
                        .font_data
                        .insert("cjk".to_owned(), egui::FontData::from_owned(data));
                    fonts
                        .families
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
