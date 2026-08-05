use std::collections::HashMap;
use std::ffi::{c_char, c_int, c_void, CStr};
use std::os::windows::ffi::OsStrExt;
use std::path::Path;
use std::process::ExitCode;
use std::sync::Arc;
use std::time::{Duration, SystemTime};

use eframe::egui;
use egui_ltreeview::{NodeBuilder, TreeView, TreeViewState};

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

        let w_path: Vec<u16> = std::ffi::OsStr::new(path)
            .encode_wide()
            .chain([0])
            .collect();
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

        entries.sort_by_key(|entry| entry.pathname.to_lowercase());
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

struct TreeNode {
    name: String,
    parent: Option<usize>,
    children: Vec<usize>,
    files: Vec<usize>,
    entry_index: Option<usize>,
}

fn build_tree(entries: &[ArchiveEntry]) -> Vec<TreeNode> {
    let mut nodes: Vec<TreeNode> = vec![TreeNode {
        name: "/".to_string(),
        parent: None,
        children: Vec::new(),
        files: Vec::new(),
        entry_index: None,
    }];
    let mut dir_map: HashMap<String, usize> = HashMap::new();
    dir_map.insert(String::new(), 0);

    for (idx, entry) in entries.iter().enumerate() {
        let parts: Vec<&str> = entry
            .pathname
            .split(['/', '\\'])
            .filter(|part| !part.is_empty())
            .collect();
        if parts.is_empty() {
            continue;
        }

        let mut parent = 0usize;
        let mut current_path = String::new();
        let directory_parts = if entry.is_dir {
            parts.len()
        } else {
            parts.len() - 1
        };

        for (depth, part) in parts.iter().take(directory_parts).enumerate() {
            if current_path.is_empty() {
                current_path = part.to_string();
            } else {
                current_path = format!("{current_path}/{part}");
            }

            if let Some(&existing) = dir_map.get(&current_path) {
                parent = existing;
                if entry.is_dir && depth == directory_parts - 1 {
                    nodes[existing].entry_index = Some(idx);
                }
            } else {
                let is_explicit_dir = entry.is_dir && depth == directory_parts - 1;
                let node_idx = nodes.len();
                nodes.push(TreeNode {
                    name: part.to_string(),
                    parent: Some(parent),
                    children: Vec::new(),
                    files: Vec::new(),
                    entry_index: is_explicit_dir.then_some(idx),
                });
                nodes[parent].children.push(node_idx);
                dir_map.insert(current_path.clone(), node_idx);
                parent = node_idx;
            }
        }

        if !entry.is_dir {
            nodes[parent].files.push(idx);
        }
    }

    nodes
}

fn entry_name(pathname: &str) -> &str {
    pathname
        .trim_end_matches(['/', '\\'])
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or(pathname)
}

#[derive(Clone, Copy)]
enum DirItem {
    Directory(usize),
    File(usize),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum FileIconKind {
    Folder,
    Image,
    Video,
    Audio,
    Pdf,
    Archive,
    Document,
    Spreadsheet,
    Presentation,
    Code,
    Text,
    Font,
    Executable,
    Generic,
}

fn file_icon_kind(name: &str) -> FileIconKind {
    let extension = name
        .rsplit_once('.')
        .filter(|(stem, _)| !stem.is_empty())
        .map(|(_, extension)| extension.to_ascii_lowercase());

    match extension.as_deref().unwrap_or_default() {
        "jpg" | "jpeg" | "png" | "gif" | "bmp" | "webp" | "svg" | "ico" | "tif" | "tiff"
        | "heic" | "avif" | "raw" | "psd" => FileIconKind::Image,
        "mp4" | "mkv" | "avi" | "mov" | "wmv" | "webm" | "m4v" | "flv" | "mpg" | "mpeg" | "3gp" => {
            FileIconKind::Video
        }
        "mp3" | "wav" | "flac" | "aac" | "ogg" | "m4a" | "wma" | "opus" | "mid" | "midi" => {
            FileIconKind::Audio
        }
        "pdf" => FileIconKind::Pdf,
        "zip" | "7z" | "rar" | "tar" | "gz" | "gzip" | "bz2" | "xz" | "zst" | "cab" | "iso"
        | "tgz" | "tbz2" | "txz" => FileIconKind::Archive,
        "doc" | "docx" | "odt" | "rtf" | "pages" => FileIconKind::Document,
        "xls" | "xlsx" | "csv" | "ods" | "numbers" => FileIconKind::Spreadsheet,
        "ppt" | "pptx" | "odp" | "key" => FileIconKind::Presentation,
        "rs" | "dart" | "py" | "js" | "jsx" | "ts" | "tsx" | "java" | "kt" | "kts" | "c" | "cc"
        | "cpp" | "h" | "hpp" | "cs" | "go" | "php" | "rb" | "swift" | "sh" | "ps1" | "bat"
        | "cmd" | "html" | "htm" | "css" | "scss" | "sass" | "less" | "vue" | "svelte" | "sql"
        | "yaml" | "yml" | "toml" | "json" | "xml" => FileIconKind::Code,
        "txt" | "md" | "log" | "ini" | "cfg" | "conf" | "nfo" => FileIconKind::Text,
        "ttf" | "otf" | "woff" | "woff2" => FileIconKind::Font,
        "exe" | "msi" | "dll" | "sys" | "com" | "appx" => FileIconKind::Executable,
        _ => FileIconKind::Generic,
    }
}

fn paint_file_icon(painter: &egui::Painter, rect: egui::Rect, kind: FileIconKind) {
    let icon = egui::Rect::from_center_size(rect.center(), egui::vec2(16.0, 16.0));

    if kind == FileIconKind::Folder {
        let tab = egui::Rect::from_min_max(
            icon.min + egui::vec2(1.0, 2.5),
            icon.min + egui::vec2(7.5, 6.0),
        );
        let body = egui::Rect::from_min_max(
            icon.min + egui::vec2(1.0, 5.0),
            icon.max - egui::vec2(1.0, 1.5),
        );
        painter.rect_filled(tab, 1.5, egui::Color32::from_rgb(239, 181, 64));
        painter.rect_filled(body, 2.0, egui::Color32::from_rgb(224, 156, 35));
        painter.line_segment(
            [body.left_top(), body.right_top()],
            egui::Stroke::new(1.0, egui::Color32::from_rgb(190, 124, 24)),
        );
        return;
    }

    let color = match kind {
        FileIconKind::Image => egui::Color32::from_rgb(53, 145, 96),
        FileIconKind::Video => egui::Color32::from_rgb(130, 88, 183),
        FileIconKind::Audio => egui::Color32::from_rgb(190, 75, 143),
        FileIconKind::Pdf => egui::Color32::from_rgb(207, 67, 61),
        FileIconKind::Archive => egui::Color32::from_rgb(126, 105, 75),
        FileIconKind::Document => egui::Color32::from_rgb(53, 112, 190),
        FileIconKind::Spreadsheet => egui::Color32::from_rgb(42, 132, 84),
        FileIconKind::Presentation => egui::Color32::from_rgb(205, 98, 49),
        FileIconKind::Code => egui::Color32::from_rgb(49, 120, 140),
        FileIconKind::Text => egui::Color32::from_rgb(102, 116, 132),
        FileIconKind::Font => egui::Color32::from_rgb(89, 91, 168),
        FileIconKind::Executable => egui::Color32::from_rgb(83, 94, 108),
        FileIconKind::Generic => egui::Color32::from_rgb(126, 140, 155),
        FileIconKind::Folder => unreachable!(),
    };
    let min = icon.min + egui::vec2(2.0, 1.0);
    let max = icon.max - egui::vec2(2.0, 1.0);
    let fold = 4.0;
    painter.add(egui::Shape::convex_polygon(
        vec![
            min,
            egui::pos2(max.x - fold, min.y),
            egui::pos2(max.x, min.y + fold),
            max,
            egui::pos2(min.x, max.y),
        ],
        color,
        egui::Stroke::new(0.8, egui::Color32::from_black_alpha(65)),
    ));
    painter.add(egui::Shape::convex_polygon(
        vec![
            egui::pos2(max.x - fold, min.y),
            egui::pos2(max.x - fold, min.y + fold),
            egui::pos2(max.x, min.y + fold),
        ],
        egui::Color32::from_white_alpha(105),
        egui::Stroke::NONE,
    ));

    let white = egui::Color32::from_white_alpha(235);
    let stroke = egui::Stroke::new(1.1, white);
    match kind {
        FileIconKind::Image => {
            painter.circle_filled(icon.min + egui::vec2(6.0, 6.0), 1.2, white);
            painter.line_segment(
                [
                    icon.min + egui::vec2(4.0, 12.0),
                    icon.min + egui::vec2(7.0, 8.5),
                ],
                stroke,
            );
            painter.line_segment(
                [
                    icon.min + egui::vec2(7.0, 8.5),
                    icon.min + egui::vec2(11.5, 12.0),
                ],
                stroke,
            );
        }
        FileIconKind::Video => {
            painter.add(egui::Shape::convex_polygon(
                vec![
                    icon.min + egui::vec2(6.0, 5.0),
                    icon.min + egui::vec2(11.5, 8.0),
                    icon.min + egui::vec2(6.0, 11.0),
                ],
                white,
                egui::Stroke::NONE,
            ));
        }
        FileIconKind::Audio => {
            painter.line_segment(
                [
                    icon.min + egui::vec2(9.5, 4.5),
                    icon.min + egui::vec2(9.5, 10.5),
                ],
                stroke,
            );
            painter.line_segment(
                [
                    icon.min + egui::vec2(9.5, 4.5),
                    icon.min + egui::vec2(12.0, 4.0),
                ],
                stroke,
            );
            painter.circle_filled(icon.min + egui::vec2(7.5, 11.0), 1.8, white);
        }
        FileIconKind::Archive => {
            for y in [5.0, 7.5, 10.0] {
                painter.rect_filled(
                    egui::Rect::from_center_size(
                        icon.min + egui::vec2(8.0, y),
                        egui::vec2(2.2, 1.5),
                    ),
                    0.2,
                    white,
                );
            }
        }
        FileIconKind::Document | FileIconKind::Text => {
            for y in [6.0, 8.5, 11.0] {
                painter.line_segment(
                    [
                        icon.min + egui::vec2(5.0, y),
                        icon.min + egui::vec2(11.0, y),
                    ],
                    stroke,
                );
            }
        }
        FileIconKind::Spreadsheet => {
            for x in [6.5, 9.5] {
                painter.line_segment(
                    [
                        icon.min + egui::vec2(x, 5.0),
                        icon.min + egui::vec2(x, 12.0),
                    ],
                    egui::Stroke::new(0.8, white),
                );
            }
            for y in [7.3, 9.7] {
                painter.line_segment(
                    [
                        icon.min + egui::vec2(4.5, y),
                        icon.min + egui::vec2(11.5, y),
                    ],
                    egui::Stroke::new(0.8, white),
                );
            }
        }
        FileIconKind::Presentation => {
            painter.rect_stroke(
                egui::Rect::from_min_max(
                    icon.min + egui::vec2(4.5, 5.0),
                    icon.min + egui::vec2(11.5, 10.0),
                ),
                0.5,
                egui::Stroke::new(0.9, white),
                egui::StrokeKind::Inside,
            );
            painter.line_segment(
                [
                    icon.min + egui::vec2(8.0, 10.0),
                    icon.min + egui::vec2(8.0, 12.0),
                ],
                stroke,
            );
        }
        FileIconKind::Pdf | FileIconKind::Code | FileIconKind::Font | FileIconKind::Executable => {
            let mark = match kind {
                FileIconKind::Pdf => "PDF",
                FileIconKind::Code => "<>",
                FileIconKind::Font => "A",
                FileIconKind::Executable => "EX",
                _ => unreachable!(),
            };
            painter.text(
                icon.center() + egui::vec2(0.0, 2.0),
                egui::Align2::CENTER_CENTER,
                mark,
                egui::FontId::proportional(if kind == FileIconKind::Pdf { 5.3 } else { 7.0 }),
                white,
            );
        }
        FileIconKind::Generic | FileIconKind::Folder => {}
    }
}

fn folder_icon(ui: &mut egui::Ui) {
    let (rect, _) = ui.allocate_exact_size(egui::vec2(16.0, 16.0), egui::Sense::hover());
    paint_file_icon(ui.painter(), rect, FileIconKind::Folder);
}

struct ArchiveApp {
    path: String,
    entries: Vec<ArchiveEntry>,
    nodes: Vec<TreeNode>,
    selected_dir: usize,
    pending_tree_selection: Option<usize>,
    col_widths: [f32; 4],
    tree_width: f32,
    drag_origin_widths: [f32; 4],
}

impl ArchiveApp {
    fn select_dir(&mut self, node_idx: usize) {
        if node_idx < self.nodes.len() {
            self.selected_dir = node_idx;
            self.pending_tree_selection = Some(node_idx);
        }
    }

    fn select_parent(&mut self) -> bool {
        let Some(parent_idx) = self.nodes[self.selected_dir].parent else {
            return false;
        };
        self.select_dir(parent_idx);
        true
    }

    fn dir_contents(&self, node_idx: usize) -> Vec<DirItem> {
        let node = &self.nodes[node_idx];
        node.children
            .iter()
            .copied()
            .map(DirItem::Directory)
            .chain(node.files.iter().copied().map(DirItem::File))
            .collect()
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
                    .inner_margin(egui::Margin::symmetric(12, 7)),
            )
            .show(ui, |ui| {
                ui.horizontal_centered(|ui| {
                    let can_go_up = self.nodes[self.selected_dir].parent.is_some();
                    let arrow_color = if can_go_up {
                        egui::Color32::WHITE
                    } else {
                        egui::Color32::from_rgb(105, 119, 136)
                    };
                    let up_button =
                        egui::Button::new(egui::RichText::new("↑").color(arrow_color).size(18.0))
                            .min_size(egui::vec2(30.0, 26.0))
                            .fill(egui::Color32::from_rgb(49, 65, 84))
                            .stroke(egui::Stroke::new(1.0, egui::Color32::from_rgb(79, 96, 116)));
                    let up_response = ui
                        .add_enabled(can_go_up, up_button)
                        .on_hover_text("Up one level");
                    if up_response.clicked() {
                        self.select_parent();
                    }
                    ui.add_space(4.0);
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
        let hover_bg = egui::Color32::from_rgb(227, 237, 250);
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

                    let (tree_rect, _) = ui
                        .allocate_exact_size(egui::vec2(tree_w, available.y), egui::Sense::hover());
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
                                    let mut state =
                                        TreeViewState::<usize>::load(ui, id).unwrap_or_default();
                                    if let Some(node_idx) = self.pending_tree_selection.take() {
                                        state.set_one_selected(node_idx);
                                        let mut ancestor = Some(node_idx);
                                        while let Some(idx) = ancestor {
                                            state.set_openness(idx, true);
                                            ancestor = self.nodes[idx].parent;
                                        }
                                        state.store(ui, id);
                                    } else if state.selected().is_empty() {
                                        state.set_one_selected(0);
                                        state.set_openness(0, true);
                                        state.store(ui, id);
                                    }
                                    let (_response, actions) =
                                        TreeView::new(id).show(ui, |builder| {
                                            self.build_tree_node(builder, 0);
                                        });
                                    for action in actions {
                                        if let egui_ltreeview::Action::SetSelected(ids) = action {
                                            if let Some(&node_idx) = ids.first() {
                                                if node_idx < self.nodes.len() {
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
                        self.tree_width =
                            (self.tree_width + splitter.1.drag_delta().x).clamp(80.0, tree_max);
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
                            let contents = self.dir_contents(self.selected_dir);
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
                            for (i, &column_x) in cumulative_x.iter().take(3).enumerate() {
                                let boundary = column_x + self.col_widths[i];
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
                                    for item in &contents {
                                        let (
                                            row_id,
                                            name,
                                            size,
                                            mtime,
                                            mode,
                                            icon_kind,
                                            target_dir,
                                        ) = match *item {
                                            DirItem::Directory(node_idx) => {
                                                let node = &self.nodes[node_idx];
                                                let entry = node
                                                    .entry_index
                                                    .map(|entry_idx| &self.entries[entry_idx]);
                                                (
                                                    ui.make_persistent_id(("dir_row", node_idx)),
                                                    node.name.clone(),
                                                    String::new(),
                                                    entry.and_then(|entry| entry.mtime),
                                                    entry
                                                        .map(|entry| {
                                                            mode_string(entry.mode, entry.is_dir)
                                                        })
                                                        .unwrap_or_default(),
                                                    FileIconKind::Folder,
                                                    Some(node_idx),
                                                )
                                            }
                                            DirItem::File(entry_idx) => {
                                                let entry = &self.entries[entry_idx];
                                                let name = entry_name(&entry.pathname).to_string();
                                                (
                                                    ui.make_persistent_id(("file_row", entry_idx)),
                                                    name.clone(),
                                                    human_size(entry.size),
                                                    entry.mtime,
                                                    mode_string(entry.mode, false),
                                                    file_icon_kind(&name),
                                                    None,
                                                )
                                            }
                                        };

                                        let row_rect = ui.allocate_space(egui::vec2(
                                            ui.available_width(),
                                            row_height,
                                        ));
                                        let row_rect = row_rect.1;

                                        let response =
                                            ui.interact(row_rect, row_id, egui::Sense::click());
                                        if response.hovered() {
                                            ui.painter().rect_filled(row_rect, 0.0, hover_bg);
                                        }
                                        if response.double_clicked() {
                                            if let Some(node_idx) = target_dir {
                                                self.select_dir(node_idx);
                                            }
                                        }

                                        let modified = format_mtime(mtime);
                                        let cols = [&name, &size, &modified, &mode];
                                        for (i, text) in cols.iter().enumerate() {
                                            let w = self.col_widths[i];
                                            let cell_rect = egui::Rect::from_min_size(
                                                egui::pos2(cumulative_x[i], row_rect.min.y),
                                                egui::vec2(w, row_height),
                                            );
                                            if i == 0 {
                                                let icon_rect = egui::Rect::from_center_size(
                                                    egui::pos2(
                                                        cell_rect.min.x + 14.0,
                                                        cell_rect.center().y,
                                                    ),
                                                    egui::vec2(18.0, 18.0),
                                                );
                                                paint_file_icon(ui.painter(), icon_rect, icon_kind);
                                            }
                                            ui.painter().with_clip_rect(cell_rect).text(
                                                egui::pos2(
                                                    cell_rect.min.x
                                                        + if i == 0 { 27.0 } else { 4.0 },
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
            builder.node(
                NodeBuilder::leaf(idx)
                    .icon(folder_icon)
                    .label(node.name.clone()),
            );
        } else {
            builder.node(
                NodeBuilder::dir(idx)
                    .default_open(idx == 0)
                    .icon(folder_icon)
                    .label(node.name.clone()),
            );
            for &child in &node.children {
                self.build_tree_node(builder, child);
            }
            builder.close_dir();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(pathname: &str, is_dir: bool) -> ArchiveEntry {
        ArchiveEntry {
            pathname: pathname.to_string(),
            size: if is_dir { 0 } else { 128 },
            mode: if is_dir { AE_IFDIR } else { 0 },
            mtime: None,
            is_dir,
        }
    }

    fn child_named(nodes: &[TreeNode], parent: usize, name: &str) -> usize {
        nodes[parent]
            .children
            .iter()
            .copied()
            .find(|&idx| nodes[idx].name == name)
            .unwrap_or_else(|| panic!("missing directory {name}"))
    }

    #[test]
    fn tree_contains_root_and_directories_only() {
        let entries = vec![
            entry("root.txt", false),
            entry("docs/", true),
            entry("docs/readme.md", false),
            entry("docs/images/logo.png", false),
            entry("empty/", true),
        ];

        let nodes = build_tree(&entries);
        let docs = child_named(&nodes, 0, "docs");
        let images = child_named(&nodes, docs, "images");
        let empty = child_named(&nodes, 0, "empty");

        assert_eq!(nodes.len(), 4);
        assert_eq!(nodes[0].name, "/");
        assert_eq!(nodes[0].parent, None);
        assert_eq!(nodes[0].files, vec![0]);
        assert_eq!(nodes[docs].parent, Some(0));
        assert_eq!(nodes[docs].entry_index, Some(1));
        assert_eq!(nodes[docs].files, vec![2]);
        assert_eq!(nodes[images].parent, Some(docs));
        assert_eq!(nodes[images].files, vec![3]);
        assert_eq!(nodes[empty].parent, Some(0));
        assert!(nodes[empty].children.is_empty());
        assert!(nodes[empty].files.is_empty());
    }

    #[test]
    fn tree_synthesizes_implicit_directories_and_windows_separators() {
        let entries = vec![entry("src\\nested\\main.rs", false)];

        let nodes = build_tree(&entries);
        let src = child_named(&nodes, 0, "src");
        let nested = child_named(&nodes, src, "nested");

        assert_eq!(nodes[nested].files, vec![0]);
        assert_eq!(entry_name(&entries[0].pathname), "main.rs");
    }

    #[test]
    fn parent_navigation_stops_at_root_and_syncs_tree_selection() {
        let entries = vec![entry("docs/readme.md", false)];
        let nodes = build_tree(&entries);
        let docs = child_named(&nodes, 0, "docs");
        let mut app = ArchiveApp {
            path: String::new(),
            entries,
            nodes,
            selected_dir: 0,
            pending_tree_selection: None,
            col_widths: [0.0; 4],
            tree_width: 0.0,
            drag_origin_widths: [0.0; 4],
        };

        app.select_dir(docs);
        assert_eq!(app.selected_dir, docs);
        assert_eq!(app.pending_tree_selection, Some(docs));
        assert!(app.select_parent());
        assert_eq!(app.selected_dir, 0);
        assert_eq!(app.pending_tree_selection, Some(0));
        assert!(!app.select_parent());
        assert_eq!(app.selected_dir, 0);
    }

    #[test]
    fn file_icons_are_selected_case_insensitively() {
        assert_eq!(file_icon_kind("photo.PNG"), FileIconKind::Image);
        assert_eq!(file_icon_kind("report.PDF"), FileIconKind::Pdf);
        assert_eq!(file_icon_kind("backup.tar.gz"), FileIconKind::Archive);
        assert_eq!(file_icon_kind("README"), FileIconKind::Generic);
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

    let nodes = build_tree(&entries);
    let selected_dir = 0;

    let title = format!("archive-view — {path}");
    let app = ArchiveApp {
        path: path.clone(),
        entries,
        nodes,
        selected_dir,
        pending_tree_selection: None,
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
                fonts.font_data.insert(
                    "msyh".to_owned(),
                    Arc::new(egui::FontData::from_owned(data)),
                );
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
