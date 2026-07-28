use std::path::Path;
use std::process::ExitCode;
use std::time::SystemTime;

use eframe::egui;
use libarchive2::{FileType, ReadArchive};

struct ArchiveEntry {
    pathname: String,
    size: i64,
    mode: u32,
    mtime: Option<SystemTime>,
    is_dir: bool,
}

fn read_archive(path: &str) -> Result<Vec<ArchiveEntry>, String> {
    let mut archive =
        ReadArchive::open(path).map_err(|e| format!("failed to open archive: {e}"))?;

    let mut entries = Vec::new();
    loop {
        match archive.next_entry() {
            Ok(Some(entry)) => {
                let is_dir = entry.file_type() == FileType::Directory;
                entries.push(ArchiveEntry {
                    pathname: entry.pathname().unwrap_or_default(),
                    size: entry.size(),
                    mode: entry.mode(),
                    mtime: entry.mtime(),
                    is_dir,
                });
            }
            Ok(None) => break,
            Err(e) => return Err(format!("failed reading archive entry: {e}")),
        }
    }

    entries.sort_by(|a, b| {
        a.pathname
            .to_lowercase()
            .cmp(&b.pathname.to_lowercase())
    });
    Ok(entries)
}

fn human_size(bytes: i64) -> String {
    if bytes <= 0 {
        return "0 B".to_string();
    }
    const UNITS: [&str; 6] = ["B", "KB", "MB", "GB", "TB", "PB"];
    let mut v = bytes as f64;
    let mut i = 0;
    while v >= 1024.0 && i < UNITS.len() - 1 {
        v /= 1024.0;
        i += 1;
    }
    if i == 0 {
        format!("{bytes} B")
    } else {
        format!("{:.1} {}", v, UNITS[i])
    }
}

fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d)
}

fn format_mtime(t: Option<SystemTime>) -> String {
    let Some(t) = t else {
        return String::new();
    };
    let Ok(dur) = t.duration_since(SystemTime::UNIX_EPOCH) else {
        return String::new();
    };
    let secs = dur.as_secs() as i64;
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    let (y, m, d) = civil_from_days(days);
    format!(
        "{y:04}-{m:02}-{d:02} {:02}:{:02}:{:02}",
        rem / 3600,
        (rem % 3600) / 60,
        rem % 60
    )
}

fn mode_string(e: &ArchiveEntry) -> String {
    let t = if e.is_dir { 'd' } else { '-' };
    format!("{t}{:03o}", e.mode & 0o777)
}

struct ArchiveApp {
    path: String,
    entries: Vec<ArchiveEntry>,
}

impl eframe::App for ArchiveApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        if ctx.input(|i| i.key_pressed(egui::Key::Escape)) {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }

        egui::TopBottomPanel::top("header").show(ctx, |ui| {
            ui.heading(&self.path);
            ui.label(format!("{} entries", self.entries.len()));
        });

        egui::CentralPanel::default().show(ctx, |ui| {
            let header = |ui: &mut egui::Ui| {
                ui.strong("Name");
                ui.strong("Size");
                ui.strong("Modified");
                ui.strong("Mode");
                ui.end_row();
            };

            egui::ScrollArea::vertical()
                .auto_shrink([false, false])
                .show(ui, |ui| {
                    egui::Grid::new("entries")
                        .striped(true)
                        .num_columns(4)
                        .spacing([16.0, 4.0])
                        .show(ui, |ui| {
                            header(ui);
                            for e in &self.entries {
                                let name = if e.is_dir {
                                    format!("{}/", e.pathname)
                                } else {
                                    e.pathname.clone()
                                };
                                ui.label(name);
                                ui.label(if e.is_dir {
                                    String::new()
                                } else {
                                    human_size(e.size)
                                });
                                ui.label(format_mtime(e.mtime));
                                ui.label(mode_string(e));
                                ui.end_row();
                            }
                        });
                });
        });
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: archive-view <FILE>");
        return ExitCode::from(1);
    }

    let path = args[1].clone();
    if !Path::new(&path).exists() {
        eprintln!("error: file not found: {path}");
        return ExitCode::from(1);
    }

    let entries = match read_archive(&path) {
        Ok(e) => e,
        Err(err) => {
            eprintln!("error: {err}");
            return ExitCode::from(1);
        }
    };

    let title = format!("archive-view — {path}");
    let app = ArchiveApp {
        path: path.clone(),
        entries,
    };

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title(&title)
            .with_inner_size([900.0, 640.0]),
        ..Default::default()
    };

    if let Err(err) = eframe::run_native(
        "archive-view",
        options,
        Box::new(move |_cc| Ok(Box::new(app) as Box<dyn eframe::App>)),
    ) {
        eprintln!("error: failed to launch GUI: {err}");
        return ExitCode::from(1);
    }

    ExitCode::SUCCESS
}
