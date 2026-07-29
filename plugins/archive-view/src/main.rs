use std::collections::HashMap;
use std::ffi::{c_char, c_int, c_void, CStr};
use std::os::windows::ffi::OsStrExt;
use std::path::Path;
use std::process::ExitCode;
use std::sync::Arc;
use std::time::{Duration, SystemTime};

use eframe::egui;
use egui_ltreeview::TreeView;

extern "C" {
    fn archive_read_new() -> *mut c_void;
    fn archive_read_support_filter_all(a: *mut c_void) -> c_int;
    fn archive_read_support_format_all(a: *mut c_void) -> c_int;
    fn archive_read_open_filename_w(a: *mut c_void, path: *const u16, block_size: usize) -> c_int;
    fn archive_read_next_header(a: *mut c_void, entry: *mut *mut c_void) -> c_int;
    fn archive_read_free(a: *mut c_void) -> c_int;
    fn archive_error_string(a: *mut c_void) -> *const c_char;
    fn archive_entry_pathname_w(entry: *mut c_void) -> *const u16;
    fn archive_entry_size(entry: *mut c_void) -> i64;
    fn archive_entry_mode(entry: *mut c_void) -> u32;
    fn archive_entry_mtime(entry: *mut c_void) -> i64;
    fn archive_entry_filetype(entry: *mut c_void) -> u32;
}

const ARCHIVE_OK: c_int = 0;
const ARCHIVE_EOF: c_int = 1;
const AE_IFDIR: u32 = 0o040000;

struct ArchiveEntry {
    pathname: String,
    size: i64,
    mode: u32,
    mtime: Option<SystemTime>,
    is_dir: bool,
}

fn read_archive(path: &str) -> Result<Vec<ArchiveEntry>, String> {
    unsafe {
        let a = archive_read_new();
        if a.is_null() {
            return Err("failed to allocate archive reader".into());
        }

        archive_read_support_filter_all(a);
        archive_read_support_format_all(a);

        let w_path: Vec<u16> = std::ffi::OsStr::new(path).encode_wide().chain([0]).collect();
        if archive_read_open_filename_w(a, w_path.as_ptr(), 10240) != ARCHIVE_OK {
            let msg = error_msg(a);
            archive_read_free(a);
            return Err(format!("failed to open archive: {msg}"));
        }

        let mut entries = Vec::new();
        let mut entry: *mut c_void = std::ptr::null_mut();

        loop {
            let r = archive_read_next_header(a, &mut entry);
            if r == ARCHIVE_EOF {
                break;
            }
            if r != ARCHIVE_OK {
                let msg = error_msg(a);
                archive_read_free(a);
                return Err(format!("failed reading archive entry: {msg}"));
            }

            let pathname = {
                let p = archive_entry_pathname_w(entry);
                if p.is_null() {
                    String::new()
                } else {
                    let mut len = 0;
                    while *p.add(len) != 0 {
                        len += 1;
                    }
                    String::from_utf16_lossy(std::slice::from_raw_parts(p, len))
                }
            };

            let mtime_secs = archive_entry_mtime(entry);
            let mtime = if mtime_secs > 0 {
                SystemTime::UNIX_EPOCH.checked_add(Duration::from_secs(mtime_secs as u64))
            } else {
                None
            };

            entries.push(ArchiveEntry {
                pathname,
                size: archive_entry_size(entry),
                mode: archive_entry_mode(entry),
                mtime,
                is_dir: archive_entry_filetype(entry) == AE_IFDIR,
            });
        }

        archive_read_free(a);

        entries.sort_by(|a, b| {
            a.pathname
                .to_lowercase()
                .cmp(&b.pathname.to_lowercase())
        });
        Ok(entries)
    }
}

unsafe fn error_msg(a: *mut c_void) -> String {
    let p = archive_error_string(a);
    if p.is_null() {
        "unknown error".into()
    } else {
        CStr::from_ptr(p).to_string_lossy().into_owned()
    }
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
    (y, m as u32, d as u32)
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

fn mode_string(mode: u32, is_dir: bool) -> String {
    let t = if is_dir { 'd' } else { '-' };
    format!("{t}{:03o}", mode & 0o777)
}

fn file_ext_color(name: &str) -> egui::Color32 {
    let ext = name.rsplit('.').next().unwrap_or("").to_lowercase();
    match ext.as_str() {
        "zip" | "7z" | "rar" | "tar" | "gz" | "xz" | "bz2" | "iso" | "cab" => {
            egui::Color32::from_rgb(156, 39, 176)
        }
        "png" | "jpg" | "jpeg" | "gif" | "bmp" | "svg" | "ico" | "webp" => {
            egui::Color32::from_rgb(76, 175, 80)
        }
        "mp3" | "wav" | "flac" | "ogg" | "mp4" | "avi" | "mkv" | "mov" => {
            egui::Color32::from_rgb(233, 30, 99)
        }
        "exe" | "dll" | "msi" | "bat" | "cmd" | "ps1" => {
            egui::Color32::from_rgb(63, 81, 181)
        }
        "rs" | "c" | "cpp" | "h" | "py" | "js" | "ts" | "java" | "go" | "toml" | "json"
        | "yaml" | "yml" | "xml" | "html" | "css" => egui::Color32::from_rgb(0, 150, 136),
        "txt" | "md" | "log" | "csv" => egui::Color32::from_rgb(96, 125, 139),
        _ => egui::Color32::from_rgb(100, 160, 230),
    }
}

fn draw_folder_icon(painter: &egui::Painter, rect: egui::Rect) {
    let w = rect.width();
    let h = rect.height();
    let tab_w = w * 0.42;
    let tab_h = h * 0.22;
    let r = 1.5;
    let fill = egui::Color32::from_rgb(255, 202, 40);
    let stroke = egui::Color32::from_rgb(230, 160, 20);
    painter.rect_filled(
        egui::Rect::from_min_size(rect.min, egui::vec2(tab_w, tab_h + r)),
        r,
        fill,
    );
    painter.rect_filled(
        egui::Rect::from_min_size(
            egui::pos2(rect.min.x, rect.min.y + tab_h),
            egui::vec2(w, h - tab_h),
        ),
        r,
        fill,
    );
    painter.rect_stroke(
        egui::Rect::from_min_size(
            egui::pos2(rect.min.x, rect.min.y + tab_h),
            egui::vec2(w, h - tab_h),
        ),
        r,
        egui::Stroke::new(1.0, stroke),
    );
}

fn draw_file_icon(painter: &egui::Painter, rect: egui::Rect, color: egui::Color32) {
    let w = rect.width();
    let h = rect.height();
    let fold = w * 0.3;
    let r = 1.0;
    let light = egui::Color32::from_rgb(
        ((color.r() as u16 + 255) / 2) as u8,
        ((color.g() as u16 + 255) / 2) as u8,
        ((color.b() as u16 + 255) / 2) as u8,
    );
    painter.rect_filled(rect, r, light);
    painter.rect_stroke(rect, r, egui::Stroke::new(1.0, color));
    let fold_pts = [
        egui::pos2(rect.max.x - fold, rect.min.y),
        egui::pos2(rect.max.x, rect.min.y + fold),
        egui::pos2(rect.max.x - fold, rect.min.y + fold),
    ];
    painter.add(egui::Shape::convex_polygon(
        fold_pts.to_vec(),
        color,
        egui::Stroke::new(0.5, color),
    ));
}

struct TreeNode {
    name: String,
    children: Vec<usize>,
    entry_index: Option<usize>,
}

fn build_tree(entries: &[ArchiveEntry]) -> (Vec<TreeNode>, Vec<usize>) {
    let mut nodes: Vec<TreeNode> = vec![TreeNode {
        name: "/".to_string(),
        children: Vec::new(),
        entry_index: None,
    }];
    let mut dir_map: HashMap<String, usize> = HashMap::new();
    dir_map.insert(String::new(), 0);

    for (idx, entry) in entries.iter().enumerate() {
        let path = entry.pathname.trim_end_matches('/');
        if path.is_empty() {
            continue;
        }

        let parts: Vec<&str> = path.split('/').collect();
        let mut parent = 0usize;
        let mut current_path = String::new();

        for (depth, part) in parts.iter().enumerate() {
            if current_path.is_empty() {
                current_path = part.to_string();
            } else {
                current_path = format!("{current_path}/{part}");
            }

            if let Some(&existing) = dir_map.get(&current_path) {
                parent = existing;
            } else {
                let is_last = depth == parts.len() - 1;
                let node_idx = nodes.len();
                nodes.push(TreeNode {
                    name: part.to_string(),
                    children: Vec::new(),
                    entry_index: if is_last { Some(idx) } else { None },
                });
                nodes[parent].children.push(node_idx);
                dir_map.insert(current_path.clone(), node_idx);
                parent = node_idx;
            }
        }
    }

    let roots = nodes[0].children.clone();
    (nodes, roots)
}

struct ArchiveApp {
    path: String,
    entries: Vec<ArchiveEntry>,
    nodes: Vec<TreeNode>,
    roots: Vec<usize>,
    selected_dir: usize,
    col_widths: [f32; 4],
    tree_width: f32,
    drag_origin_widths: [f32; 4],
}

impl ArchiveApp {
    fn dir_children(&self, node_idx: usize) -> Vec<usize> {
        self.nodes[node_idx].children.clone()
    }
}

impl eframe::App for ArchiveApp {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        let ctx = ui.ctx().clone();
        if ctx.input(|i| i.key_pressed(egui::Key::Escape)) {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }

        egui::Panel::top("header")
            .frame(
                egui::Frame::NONE
                    .fill(egui::Color32::from_rgb(38, 50, 66))
                    .inner_margin(egui::Margin::symmetric(12.0, 7.0)),
            )
            .show(ui, |ui| {
                ui.horizontal_centered(|ui| {
                    ui.heading(
                        egui::RichText::new(&self.path)
                            .color(egui::Color32::WHITE)
                            .strong(),
                    );
                    ui.add_space(16.0);
                    ui.label(
                        egui::RichText::new(format!("{} entries", self.entries.len()))
                            .color(egui::Color32::from_rgb(158, 178, 200)),
                    );
                });
            });

        let table_bg = egui::Color32::from_rgb(247, 249, 252);
        let tree_bg = egui::Color32::from_rgb(240, 244, 248);
        let text_color = egui::Color32::from_rgb(38, 50, 66);
        let text_secondary = egui::Color32::from_rgb(110, 122, 138);
        let folder_color = egui::Color32::from_rgb(245, 166, 35);
        let hover_bg = egui::Color32::from_rgb(227, 237, 250);
        let alt_row_bg = egui::Color32::from_rgb(241, 245, 249);
        let header_bg = egui::Color32::from_rgb(232, 238, 244);
        let divider_color = egui::Color32::from_rgb(213, 221, 230);
        let accent = egui::Color32::from_rgb(21, 101, 192);

        egui::CentralPanel::default()
            .frame(egui::Frame::NONE.fill(table_bg))
            .show(ui, |ui| {
                let available = ui.available_size();

                let splitter_w = 5.0;
                let tree_max = (available.x - splitter_w - 120.0).max(80.0);
                let tree_w = self.tree_width.clamp(80.0, tree_max);
                let table_w = (available.x - tree_w - splitter_w).max(0.0);

                ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = 0.0;

                    let (tree_rect, _) = ui.allocate_exact_size(
                        egui::vec2(tree_w, available.y),
                        egui::Sense::hover(),
                    );
                    ui.scope_builder(
                        egui::UiBuilder::new()
                            .id_salt("tree_panel")
                            .max_rect(tree_rect)
                            .layout(egui::Layout::top_down(egui::Align::Min)),
                        |ui| {
                            ui.painter().rect_filled(tree_rect, 0.0, tree_bg);
                            ui.painter().vline(
                                tree_rect.max.x,
                                tree_rect.y_range(),
                                egui::Stroke::new(1.0, divider_color),
                            );
                            egui::ScrollArea::both()
                                .id_salt("tree_scroll")
                                .auto_shrink([false, false])
                                .show(ui, |ui| {
                                    let id = ui.make_persistent_id("archive_tree");
                                    let (_response, actions) =
                                        TreeView::new(id).show(ui, |builder| {
                                            for &root in &self.roots {
                                                self.build_tree_node(builder, root);
                                            }
                                        });
                                    for action in actions {
                                        if let egui_ltreeview::Action::SetSelected(ids) = action {
                                            if let Some(&node_idx) = ids.first() {
                                                if node_idx < self.nodes.len()
                                                    && !self.nodes[node_idx].children.is_empty()
                                                {
                                                    self.selected_dir = node_idx;
                                                }
                                            }
                                        }
                                    }
                                });
                        },
                    );

                    let splitter = ui.allocate_exact_size(
                        egui::vec2(splitter_w, available.y),
                        egui::Sense::drag(),
                    );
                    let sr = splitter.1.rect;
                    let is_active = splitter.1.dragged() || splitter.1.hovered();
                    ui.painter().rect_filled(
                        sr,
                        0.0,
                        if is_active { accent } else { divider_color },
                    );
                    if is_active {
                        ctx.output_mut(|o| {
                            o.cursor_icon = egui::CursorIcon::ResizeColumn;
                        });
                    }
                    if splitter.1.dragged() {
                        self.tree_width = (self.tree_width + splitter.1.drag_delta().x)
                            .clamp(80.0, tree_max);
                    }

                    let (table_rect, _) = ui.allocate_exact_size(
                        egui::vec2(table_w, available.y),
                        egui::Sense::hover(),
                    );
                    ui.scope_builder(
                        egui::UiBuilder::new()
                            .id_salt("table_panel")
                            .max_rect(table_rect)
                            .layout(egui::Layout::top_down(egui::Align::Min)),
                        |ui| {
                            let row_height = ui.spacing().interact_size.y + 4.0;
                            let children = self.dir_children(self.selected_dir);
                            let headers = ["Name", "Size", "Modified", "Mode"];

                            // Column x positions shared by the header and the rows.
                            let mut cumulative_x = [0.0f32; 4];
                            cumulative_x[0] = table_rect.min.x;
                            for i in 1..4 {
                                cumulative_x[i] = cumulative_x[i - 1] + self.col_widths[i - 1];
                            }

                            let (hdr_rect, _) = ui.allocate_exact_size(
                                egui::vec2(table_w, row_height),
                                egui::Sense::hover(),
                            );
                            ui.painter().rect_filled(hdr_rect, 0.0, header_bg);
                            let header_font = egui::TextStyle::Body.resolve(ui.style());
                            for (i, header) in headers.iter().enumerate() {
                                ui.painter().text(
                                    egui::pos2(cumulative_x[i] + 8.0, hdr_rect.center().y),
                                    egui::Align2::LEFT_CENTER,
                                    *header,
                                    header_font.clone(),
                                    text_secondary,
                                );
                            }

                            // Column dividers with drag handles.
                            for i in 0..3 {
                                let boundary = cumulative_x[i] + self.col_widths[i];
                                let handle_rect = egui::Rect::from_min_size(
                                    egui::pos2(boundary - 3.0, hdr_rect.min.y),
                                    egui::vec2(6.0, row_height),
                                );
                                let resp = ui.interact(
                                    handle_rect,
                                    ui.make_persistent_id(("col_handle", i)),
                                    egui::Sense::drag(),
                                );
                                if resp.hovered() || resp.dragged() {
                                    ctx.output_mut(|o| {
                                        o.cursor_icon = egui::CursorIcon::ResizeColumn;
                                    });
                                }
                                if resp.drag_started() {
                                    self.drag_origin_widths = self.col_widths;
                                }
                                if let Some(total) = resp.total_drag_delta() {
                                    let dx = total.x;
                                    self.col_widths[i] =
                                        (self.drag_origin_widths[i] + dx).max(40.0);
                                    self.col_widths[i + 1] =
                                        (self.drag_origin_widths[i + 1] - dx).max(40.0);
                                }
                                ui.painter().vline(
                                    boundary,
                                    hdr_rect.y_range(),
                                    egui::Stroke::new(1.0, divider_color),
                                );
                            }

                            ui.painter().hline(
                                hdr_rect.x_range(),
                                hdr_rect.max.y,
                                egui::Stroke::new(1.0, divider_color),
                            );

                            egui::ScrollArea::vertical()
                                .id_salt("table_scroll")
                                .auto_shrink([false, false])
                                .show(ui, |ui| {
                                    for &child_idx in &children {
                                        let node = &self.nodes[child_idx];
                                        let entry = node.entry_index.map(|i| &self.entries[i]);

                                        let is_dir = !node.children.is_empty()
                                            || entry.map(|e| e.is_dir).unwrap_or(false);
                                        let name = if is_dir {
                                            format!("{}/", node.name)
                                        } else {
                                            node.name.clone()
                                        };
                                        let size = if is_dir {
                                            String::new()
                                        } else {
                                            entry
                                                .map(|e| human_size(e.size))
                                                .unwrap_or_default()
                                        };
                                        let mtime = entry
                                            .and_then(|e| e.mtime)
                                            .map(Some)
                                            .unwrap_or(None);
                                        let mode = entry
                                            .map(|e| mode_string(e.mode, e.is_dir))
                                            .unwrap_or_default();

                                        let row_rect = ui.allocate_space(egui::vec2(
                                            ui.available_width(),
                                            row_height,
                                        ));
                                        let row_rect = row_rect.1;

                                        let response = ui.interact(
                                            row_rect,
                                            ui.make_persistent_id(child_idx),
                                            egui::Sense::click(),
                                        );
                                        if response.hovered() {
                                            ui.painter()
                                                .rect_filled(row_rect, 0.0, hover_bg);
                                        }
                                        if response.double_clicked() && is_dir {
                                            self.selected_dir = child_idx;
                                        }

                                        let cols = [
                                            &name,
                                            &size,
                                            &format_mtime(mtime),
                                            &mode,
                                        ];
                                        for (i, text) in cols.iter().enumerate() {
                                            let w = self.col_widths[i];
                                            let cell_rect = egui::Rect::from_min_size(
                                                egui::pos2(cumulative_x[i], row_rect.min.y),
                                                egui::vec2(w, row_height),
                                            );
                                            ui.painter().text(
                                                egui::pos2(
                                                    cell_rect.min.x + 4.0,
                                                    cell_rect.center().y,
                                                ),
                                                egui::Align2::LEFT_CENTER,
                                                *text,
                                                egui::FontId::monospace(13.0),
                                                text_color,
                                            );
                                        }
                                    }
                                });
                        },
                    );
                });
            });
    }
}

impl ArchiveApp {
    fn build_tree_node(&self, builder: &mut egui_ltreeview::TreeViewBuilder<usize>, idx: usize) {
        let node = &self.nodes[idx];
        if node.children.is_empty() {
            builder.leaf(idx, &node.name);
        } else {
            builder.dir(idx, &node.name);
            for &child in &node.children {
                if !self.nodes[child].children.is_empty() {
                    self.build_tree_node(builder, child);
                }
            }
            builder.close_dir();
        }
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

    let (nodes, roots) = build_tree(&entries);
    let selected_dir = if roots.len() == 1 { roots[0] } else { 0 };

    let title = format!("archive-view — {path}");
    let app = ArchiveApp {
        path: path.clone(),
        entries,
        nodes,
        roots,
        selected_dir,
        col_widths: [300.0, 100.0, 100.0, 100.0],
        tree_width: 280.0,
        drag_origin_widths: [0.0; 4],
    };

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title(&title)
            .with_inner_size([1000.0, 680.0]),
        ..Default::default()
    };

    if let Err(err) = eframe::run_native(
        "archive-view",
        options,
        Box::new(move |cc| {
            let mut fonts = egui::FontDefinitions::default();
            let font_path = "C:\\Windows\\Fonts\\msyh.ttc";
            if let Ok(data) = std::fs::read(font_path) {
                fonts
                    .font_data
                    .insert("msyh".to_owned(), Arc::new(egui::FontData::from_owned(data)));
                fonts
                    .families
                    .entry(egui::FontFamily::Proportional)
                    .or_default()
                    .insert(0, "msyh".to_owned());
                fonts
                    .families
                    .entry(egui::FontFamily::Monospace)
                    .or_default()
                    .push("msyh".to_owned());
            }
            cc.egui_ctx.set_fonts(fonts);
            // Always-visible scroll bars (default floating style is hard to spot).
            cc.egui_ctx.style_mut_of(egui::Theme::Light, |style| {
                style.spacing.scroll = egui::style::ScrollStyle::solid();
            });
            cc.egui_ctx.style_mut_of(egui::Theme::Dark, |style| {
                style.spacing.scroll = egui::style::ScrollStyle::solid();
            });
            Ok(Box::new(app) as Box<dyn eframe::App>)
        }),
    ) {
        eprintln!("error: failed to launch GUI: {err}");
        return ExitCode::from(1);
    }

    ExitCode::SUCCESS
}
