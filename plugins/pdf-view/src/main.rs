use std::env;
use std::fs::OpenOptions;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::OnceLock;

use eframe::egui;
use egui::{
    Color32, ColorImage, Context, Key, Pos2, Rect, Sense, TextureHandle, TextureOptions, Vec2,
};
use image::DynamicImage;
use pdfium_render::prelude::*;
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};

const DEFAULT_WIDTH: f32 = 960.0;
const DEFAULT_HEIGHT: f32 = 720.0;
const MIN_ZOOM: f32 = 0.1;
const MAX_ZOOM: f32 = 8.0;
const RENDER_SCALE: f32 = 1.5;
const MAX_RENDER_WIDTH: u16 = 8192;

static PDFIUM: OnceLock<Result<Pdfium, String>> = OnceLock::new();

fn debug_log(message: impl AsRef<str>) {
    let message = message.as_ref();
    eprintln!("{message}");
    let Some(directory) = env::current_exe()
        .ok()
        .and_then(|path| path.parent().map(Path::to_path_buf))
    else {
        return;
    };
    if let Ok(mut file) = OpenOptions::new()
        .create(true)
        .append(true)
        .open(directory.join("pdf-view.log"))
    {
        let _ = writeln!(file, "{message}");
    }
}

struct Args {
    file: PathBuf,
    placement: Option<WindowPlacement>,
}

fn usage() -> &'static str {
    "Usage: pdf-view <PDF_FILE> [--window-placement JSON]"
}

fn parse_args() -> Result<Args, String> {
    let args: Vec<String> = env::args().skip(1).collect();
    let mut file = None;
    let mut placement = None;
    let mut i = 0;

    while i < args.len() {
        match args[i].as_str() {
            WINDOW_PLACEMENT_ARGUMENT => {
                i += 1;
                let value = args.get(i).ok_or_else(|| {
                    format!(
                        "{WINDOW_PLACEMENT_ARGUMENT} requires a JSON value\n{}",
                        usage()
                    )
                })?;
                let parsed = WindowPlacement::from_json(value)?;
                if placement.replace(parsed).is_some() {
                    return Err(format!(
                        "{WINDOW_PLACEMENT_ARGUMENT} may only be specified once\n{}",
                        usage()
                    ));
                }
            }
            value if value.starts_with('-') => {
                return Err(format!("unknown option: {value}\n{}", usage()));
            }
            value => {
                if file.replace(PathBuf::from(value)).is_some() {
                    return Err(format!("unexpected argument: {value}\n{}", usage()));
                }
            }
        }
        i += 1;
    }

    let file = file.ok_or_else(|| usage().to_string())?;
    if !file.is_file() {
        return Err(format!("file does not exist: {}", file.display()));
    }

    Ok(Args { file, placement })
}

fn pdfium_library_path() -> Result<PathBuf, String> {
    if let Some(path) = env::var_os("PDFIUM_PATH") {
        let path = PathBuf::from(path);
        let candidate = if path.is_dir() {
            path.join(Pdfium::pdfium_platform_library_name())
        } else {
            path
        };
        if candidate.is_file() {
            return Ok(candidate);
        }
    }

    let exe_dir = env::current_exe()
        .ok()
        .and_then(|path| path.parent().map(Path::to_path_buf));
    let current_dir = env::current_dir().ok();

    for dir in exe_dir.into_iter().chain(current_dir) {
        let candidate = dir.join(Pdfium::pdfium_platform_library_name());
        if candidate.is_file() {
            return Ok(candidate);
        }
    }

    Err("pdfium.dll was not found next to pdf-view.exe; set PDFIUM_PATH to override".to_string())
}

fn pdfium() -> Result<&'static Pdfium, String> {
    PDFIUM
        .get_or_init(|| {
            let path = pdfium_library_path()?;
            let bindings = Pdfium::bind_to_library(&path).map_err(|error| {
                format!("failed to load PDFium from {}: {error}", path.display())
            })?;
            Ok(Pdfium::new(bindings))
        })
        .as_ref()
        .map_err(Clone::clone)
}

fn document_info(path: &Path) -> Result<(usize, Vec<(f32, f32)>), String> {
    let pdfium = pdfium()?;
    let document = pdfium
        .load_pdf_from_file(path, None)
        .map_err(|error| format!("failed to open {}: {error}", path.display()))?;
    let count = document.pages().len() as usize;
    if count == 0 {
        return Err("PDF contains no pages".to_string());
    }

    let mut page_sizes = Vec::with_capacity(count);
    for page in document.pages().iter() {
        page_sizes.push((page.width().value, page.height().value));
    }
    Ok((count, page_sizes))
}

fn render_page(
    path: &Path,
    page_index: usize,
    target_width: u16,
    rotation: u8,
) -> Result<ColorImage, String> {
    let pdfium = pdfium()?;
    let document = pdfium
        .load_pdf_from_file(path, None)
        .map_err(|error| format!("failed to open PDF: {error}"))?;
    let page = document
        .pages()
        .get(page_index as PdfPageIndex)
        .map_err(|error| format!("failed to open page {}: {error}", page_index + 1))?;
    let bitmap = page
        .render_with_config(
            &PdfRenderConfig::new()
                .set_target_width(target_width as i32)
                .render_form_data(true)
                .render_annotations(true),
        )
        .map_err(|error| format!("failed to render page {}: {error}", page_index + 1))?;

    let mut image = bitmap
        .as_image()
        .map_err(|error| format!("failed to convert rendered page: {error}"))?;
    image = match rotation % 4 {
        1 => image.rotate90(),
        2 => image.rotate180(),
        3 => image.rotate270(),
        _ => image,
    };
    dynamic_to_color_image(image)
}

fn dynamic_to_color_image(image: DynamicImage) -> Result<ColorImage, String> {
    let rgba = image.to_rgba8();
    let width = usize::try_from(rgba.width()).map_err(|_| "rendered page is too wide")?;
    let height = usize::try_from(rgba.height()).map_err(|_| "rendered page is too tall")?;
    Ok(ColorImage::from_rgba_unmultiplied(
        [width, height],
        rgba.as_raw(),
    ))
}

#[derive(Clone, Copy, PartialEq)]
enum FitMode {
    Page,
    Width,
    Custom,
}

#[derive(Clone)]
struct TextGlyph {
    text: String,
    left: f32,
    bottom: f32,
    right: f32,
    top: f32,
}

struct TextSelection {
    page: usize,
    start: Pos2,
    end: Pos2,
}

impl TextSelection {
    fn rect(&self) -> Rect {
        Rect::from_two_pos(self.start, self.end)
    }
}

fn load_text_glyphs(path: &Path, page_index: usize) -> Result<Vec<TextGlyph>, String> {
    let pdfium = pdfium()?;
    let document = pdfium
        .load_pdf_from_file(path, None)
        .map_err(|error| format!("failed to open PDF text layer: {error}"))?;
    let page = document
        .pages()
        .get(page_index as PdfPageIndex)
        .map_err(|error| format!("failed to open page {} text layer: {error}", page_index + 1))?;
    let text = page
        .text()
        .map_err(|error| format!("failed to load page {} text: {error}", page_index + 1))?;

    let mut glyphs = Vec::with_capacity(text.chars().len());
    for character in text.chars().iter() {
        let Some(value) = character.unicode_string() else {
            continue;
        };
        let Ok(bounds) = character.tight_bounds() else {
            continue;
        };
        glyphs.push(TextGlyph {
            text: value,
            left: bounds.left().value,
            bottom: bounds.bottom().value,
            right: bounds.right().value,
            top: bounds.top().value,
        });
    }
    Ok(glyphs)
}

struct PdfViewer {
    path: PathBuf,
    page_count: usize,
    page_sizes: Vec<(f32, f32)>,
    page: usize,
    rotation: u8,
    zoom: f32,
    fit_mode: FitMode,
    textures: Vec<Option<TextureHandle>>,
    rendered_keys: Vec<Option<(u8, u16)>>,
    errors: Vec<Option<String>>,
    text_glyphs: Vec<Option<Vec<TextGlyph>>>,
    selection: Option<TextSelection>,
    selected_text: String,
    pending_scroll_page: Option<usize>,
}

impl PdfViewer {
    fn new(path: PathBuf, page_count: usize, page_sizes: Vec<(f32, f32)>) -> Self {
        Self {
            path,
            page_count,
            page_sizes,
            page: 0,
            rotation: 0,
            zoom: 1.0,
            fit_mode: FitMode::Custom,
            textures: vec![None; page_count],
            rendered_keys: vec![None; page_count],
            errors: vec![None; page_count],
            text_glyphs: vec![None; page_count],
            selection: None,
            selected_text: String::new(),
            pending_scroll_page: None,
        }
    }

    fn page_size_at(&self, page_index: usize) -> Vec2 {
        let (width, height) = self.page_sizes[page_index];
        if self.rotation.is_multiple_of(2) {
            Vec2::new(width, height)
        } else {
            Vec2::new(height, width)
        }
    }

    fn display_scale_at(&self, page_index: usize, available: Vec2) -> f32 {
        let page = self.page_size_at(page_index);
        match self.fit_mode {
            FitMode::Page => (available.x / page.x).min(available.y / page.y).min(1.0),
            FitMode::Width => (available.x / page.x).min(MAX_ZOOM),
            FitMode::Custom => self.zoom,
        }
        .clamp(MIN_ZOOM, MAX_ZOOM)
    }

    fn invalidate(&mut self) {
        self.rendered_keys.fill(None);
        self.errors.fill(None);
        self.selection = None;
        self.selected_text.clear();
    }

    fn change_page(&mut self, delta: isize) {
        self.page = self
            .page
            .saturating_add_signed(delta)
            .min(self.page_count - 1);
        self.pending_scroll_page = Some(self.page);
    }

    fn set_zoom(&mut self, zoom: f32) {
        self.zoom = zoom.clamp(MIN_ZOOM, MAX_ZOOM);
        self.fit_mode = FitMode::Custom;
        self.invalidate();
    }

    fn ensure_texture(&mut self, ctx: &Context, page_index: usize, source_display_width: f32) {
        let requested_width = (source_display_width * RENDER_SCALE)
            .round()
            .clamp(64.0, MAX_RENDER_WIDTH as f32) as u16;
        let render_width = requested_width.div_ceil(32) * 32;
        let key = (self.rotation, render_width);
        if self.rendered_keys[page_index] == Some(key) {
            return;
        }

        match render_page(&self.path, page_index, render_width, self.rotation) {
            Ok(image) => {
                self.textures[page_index] = Some(ctx.load_texture(
                    format!("pdf-page-{page_index}"),
                    image,
                    TextureOptions::LINEAR,
                ));
                self.rendered_keys[page_index] = Some(key);
                self.errors[page_index] = None;
            }
            Err(error) => {
                self.textures[page_index] = None;
                self.rendered_keys[page_index] = Some(key);
                self.errors[page_index] = Some(error);
            }
        }
    }

    fn ensure_text_glyphs(&mut self, page_index: usize) -> Result<(), String> {
        if self.text_glyphs[page_index].is_none() {
            let glyphs = load_text_glyphs(&self.path, page_index)?;
            debug_log(format!(
                "[pdf-view] page {} text layer loaded: {} glyphs",
                page_index + 1,
                glyphs.len()
            ));
            self.text_glyphs[page_index] = Some(glyphs);
        }
        Ok(())
    }

    fn glyph_display_rect(&self, page_index: usize, glyph: &TextGlyph, scale: f32) -> Rect {
        let (_, page_height) = self.page_sizes[page_index];
        let source_size = Vec2::new(self.page_sizes[page_index].0 * scale, page_height * scale);
        let source = Rect::from_min_max(
            Pos2::new(glyph.left * scale, (page_height - glyph.top) * scale),
            Pos2::new(glyph.right * scale, (page_height - glyph.bottom) * scale),
        );

        match self.rotation % 4 {
            1 => Rect::from_min_max(
                Pos2::new(source_size.y - source.max.y, source.min.x),
                Pos2::new(source_size.y - source.min.y, source.max.x),
            ),
            2 => Rect::from_min_max(
                Pos2::new(source_size.x - source.max.x, source_size.y - source.max.y),
                Pos2::new(source_size.x - source.min.x, source_size.y - source.min.y),
            ),
            3 => Rect::from_min_max(
                Pos2::new(source.min.y, source_size.x - source.max.x),
                Pos2::new(source.max.y, source_size.x - source.min.x),
            ),
            _ => source,
        }
    }

    fn update_selected_text(&mut self, page_index: usize, scale: f32) {
        let Some(selection) = &self.selection else {
            return;
        };
        let Some(glyphs) = &self.text_glyphs[page_index] else {
            return;
        };
        let selection_rect = selection.rect();
        self.selected_text = glyphs
            .iter()
            .filter(|glyph| {
                self.glyph_display_rect(page_index, glyph, scale)
                    .intersects(selection_rect)
            })
            .map(|glyph| glyph.text.as_str())
            .collect();
    }

    fn copy_selection(&self, ctx: &Context) {
        if self.selected_text.is_empty() {
            debug_log("[pdf-view] Ctrl+C ignored: selection contains no text");
            return;
        }

        ctx.copy_text(self.selected_text.clone());
        match arboard::Clipboard::new()
            .and_then(|mut clipboard| clipboard.set_text(self.selected_text.clone()))
        {
            Ok(()) => debug_log(format!(
                "[pdf-view] copied {} chars to clipboard: {:?}",
                self.selected_text.chars().count(),
                self.selected_text
            )),
            Err(error) => debug_log(format!(
                "[pdf-view] clipboard write failed for {} chars: {error}",
                self.selected_text.chars().count()
            )),
        }
    }

    fn keyboard(&mut self, ctx: &Context) {
        if ctx.input(|input| input.key_pressed(Key::Escape)) {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }
        if ctx.input(|input| {
            input
                .events
                .iter()
                .any(|event| matches!(event, egui::Event::Copy))
                || (input.modifiers.ctrl && input.key_pressed(Key::C))
        }) {
            debug_log("[pdf-view] copy shortcut detected");
            self.copy_selection(ctx);
        }
        if ctx.input(|input| input.key_pressed(Key::PageDown) || input.key_pressed(Key::ArrowRight))
        {
            self.change_page(1);
        }
        if ctx.input(|input| input.key_pressed(Key::PageUp) || input.key_pressed(Key::ArrowLeft)) {
            self.change_page(-1);
        }
        if ctx.input(|input| input.key_pressed(Key::Home)) {
            self.page = 0;
            self.pending_scroll_page = Some(self.page);
        }
        if ctx.input(|input| input.key_pressed(Key::End)) {
            self.page = self.page_count - 1;
            self.pending_scroll_page = Some(self.page);
        }
        if ctx.input(|input| input.key_pressed(Key::R)) {
            self.rotation = (self.rotation + 1) % 4;
            self.invalidate();
        }
        if ctx.input(|input| input.key_pressed(Key::F)) {
            self.fit_mode = FitMode::Page;
            self.invalidate();
        }
        if ctx.input(|input| input.key_pressed(Key::W)) {
            self.fit_mode = FitMode::Width;
            self.invalidate();
        }
        if ctx.input(|input| input.key_pressed(Key::Plus) || input.key_pressed(Key::Equals)) {
            self.set_zoom(self.zoom * 1.2);
        }
        if ctx.input(|input| input.key_pressed(Key::Minus)) {
            self.set_zoom(self.zoom / 1.2);
        }
        let zoom_delta = ctx.input(|input| {
            if input.modifiers.ctrl {
                input.raw_scroll_delta.y
            } else {
                0.0
            }
        });
        if zoom_delta != 0.0 {
            self.set_zoom(self.zoom * if zoom_delta > 0.0 { 1.1 } else { 1.0 / 1.1 });
        }
    }
}

impl eframe::App for PdfViewer {
    fn update(&mut self, ctx: &Context, _frame: &mut eframe::Frame) {
        self.keyboard(ctx);

        egui::TopBottomPanel::top("toolbar")
            .exact_height(40.0)
            .show(ctx, |ui| {
                ui.horizontal_centered(|ui| {
                    if ui
                        .add_enabled(self.page > 0, egui::Button::new("<"))
                        .clicked()
                    {
                        self.change_page(-1);
                    }
                    ui.label(format!("{} / {}", self.page + 1, self.page_count));
                    if ui
                        .add_enabled(self.page + 1 < self.page_count, egui::Button::new(">"))
                        .clicked()
                    {
                        self.change_page(1);
                    }
                    ui.separator();
                    if ui.button("-").on_hover_text("Zoom out").clicked() {
                        self.set_zoom(self.zoom / 1.2);
                    }
                    ui.label(format!("{:.0}%", self.zoom * 100.0));
                    if ui.button("+").on_hover_text("Zoom in").clicked() {
                        self.set_zoom(self.zoom * 1.2);
                    }
                    if ui
                        .selectable_label(self.fit_mode == FitMode::Page, "Fit page")
                        .clicked()
                    {
                        self.fit_mode = FitMode::Page;
                        self.invalidate();
                    }
                    if ui
                        .selectable_label(self.fit_mode == FitMode::Width, "Fit width")
                        .clicked()
                    {
                        self.fit_mode = FitMode::Width;
                        self.invalidate();
                    }
                    if ui.button("Rotate").clicked() {
                        self.rotation = (self.rotation + 1) % 4;
                        self.invalidate();
                    }
                    if ui.button("Copy").on_hover_text("Copy selection").clicked() {
                        self.copy_selection(ctx);
                    }
                });
            });

        egui::CentralPanel::default()
            .frame(egui::Frame::default().fill(Color32::from_rgb(42, 44, 48)))
            .show(ctx, |ui| {
                let available = (ui.available_size() - Vec2::splat(24.0)).max(Vec2::splat(1.0));
                let content_width = (0..self.page_count)
                    .map(|page_index| {
                        self.page_size_at(page_index).x
                            * self.display_scale_at(page_index, available)
                    })
                    .fold(available.x, f32::max)
                    + 24.0;
                let mut closest_page = self.page;
                let mut closest_distance = f32::INFINITY;
                let mut page_y = 0.0;
                egui::ScrollArea::both()
                    .auto_shrink([false, false])
                    .drag_to_scroll(false)
                    .show_viewport(ui, |ui, viewport| {
                        ui.set_min_width(content_width);
                        for page_index in 0..self.page_count {
                            let scale = self.display_scale_at(page_index, available);
                            let display_size = self.page_size_at(page_index) * scale;
                            let page_area_height = display_size.y + 24.0;
                            let page_center = page_y + page_area_height * 0.5;
                            let distance = (page_center - viewport.center().y).abs();
                            if distance < closest_distance {
                                closest_page = page_index;
                                closest_distance = distance;
                            }

                            let is_near_viewport = page_y < viewport.max.y + viewport.height()
                                && page_y + page_area_height > viewport.min.y - viewport.height();
                            if is_near_viewport {
                                let source_display_width = self.page_sizes[page_index].0 * scale;
                                self.ensure_texture(ctx, page_index, source_display_width);
                            }

                            let page_response = ui.allocate_ui_with_layout(
                                Vec2::new(content_width, page_area_height),
                                egui::Layout::top_down(egui::Align::Center),
                                |ui| {
                                    ui.add_space(12.0);
                                    let selection_rect = self
                                        .selection
                                        .as_ref()
                                        .filter(|selection| selection.page == page_index)
                                        .map(TextSelection::rect);
                                    if let Some(error) = &self.errors[page_index] {
                                        let (rect, response) = ui.allocate_exact_size(
                                            display_size,
                                            Sense::click_and_drag(),
                                        );
                                        ui.painter().rect_filled(rect, 0.0, Color32::WHITE);
                                        ui.painter().text(
                                            rect.center(),
                                            egui::Align2::CENTER_CENTER,
                                            error,
                                            egui::FontId::proportional(14.0),
                                            Color32::DARK_RED,
                                        );
                                        response
                                    } else if let Some(texture) = &self.textures[page_index] {
                                        let response = ui.add(
                                            egui::Image::new(texture)
                                                .fit_to_exact_size(display_size)
                                                .bg_fill(Color32::WHITE)
                                                .sense(Sense::click_and_drag()),
                                        );
                                        if let (Some(selection_rect), Some(glyphs)) =
                                            (selection_rect, &self.text_glyphs[page_index])
                                        {
                                            let painter = ui.painter();
                                            for glyph in glyphs.iter().filter(|glyph| {
                                                self.glyph_display_rect(page_index, glyph, scale)
                                                    .intersects(selection_rect)
                                            }) {
                                                let glyph_rect = self
                                                    .glyph_display_rect(page_index, glyph, scale)
                                                    .translate(response.rect.min.to_vec2());
                                                painter.rect_filled(
                                                    glyph_rect,
                                                    0.0,
                                                    Color32::from_rgba_unmultiplied(
                                                        70, 130, 220, 110,
                                                    ),
                                                );
                                            }
                                            painter.rect_stroke(
                                                selection_rect
                                                    .translate(response.rect.min.to_vec2()),
                                                0.0,
                                                egui::Stroke::new(
                                                    1.0_f32,
                                                    Color32::from_rgb(105, 165, 255),
                                                ),
                                            );
                                        }
                                        response
                                    } else {
                                        let (rect, response) = ui.allocate_exact_size(
                                            display_size,
                                            Sense::click_and_drag(),
                                        );
                                        ui.painter().rect_filled(rect, 0.0, Color32::WHITE);
                                        response
                                    }
                                },
                            );
                            if page_response.inner.drag_started() {
                                self.selection = None;
                                self.selected_text.clear();
                                if let Err(error) = self.ensure_text_glyphs(page_index) {
                                    debug_log(format!(
                                        "[pdf-view] page {} text layer load failed: {error}",
                                        page_index + 1
                                    ));
                                } else {
                                    if let Some(pointer) =
                                        page_response.inner.interact_pointer_pos()
                                    {
                                        let start = Pos2::new(
                                            (pointer.x - page_response.inner.rect.min.x)
                                                .clamp(0.0, display_size.x),
                                            (pointer.y - page_response.inner.rect.min.y)
                                                .clamp(0.0, display_size.y),
                                        );
                                        self.selection = Some(TextSelection {
                                            page: page_index,
                                            start,
                                            end: start,
                                        });
                                    }
                                }
                            }
                            if page_response.inner.dragged() {
                                if let (Some(selection), Some(pointer)) = (
                                    self.selection.as_mut(),
                                    page_response.inner.interact_pointer_pos(),
                                ) {
                                    if selection.page == page_index {
                                        selection.end = Pos2::new(
                                            (pointer.x - page_response.inner.rect.min.x)
                                                .clamp(0.0, display_size.x),
                                            (pointer.y - page_response.inner.rect.min.y)
                                                .clamp(0.0, display_size.y),
                                        );
                                        self.update_selected_text(page_index, scale);
                                    }
                                }
                            }
                            if page_response.inner.drag_stopped()
                                && self
                                    .selection
                                    .as_ref()
                                    .is_some_and(|selection| selection.page == page_index)
                            {
                                debug_log(format!(
                                    "[pdf-view] page {} selection: {} chars: {:?}",
                                    page_index + 1,
                                    self.selected_text.chars().count(),
                                    self.selected_text
                                ));
                            }
                            if self.pending_scroll_page == Some(page_index) {
                                ui.scroll_to_rect(
                                    page_response.inner.rect,
                                    Some(egui::Align::Center),
                                );
                                self.pending_scroll_page = None;
                            }
                            page_y += page_area_height;
                        }
                    });
                self.page = closest_page;
                self.zoom = self.display_scale_at(self.page, available);
            });

        let file_name = self
            .path
            .file_name()
            .map(|name| name.to_string_lossy())
            .unwrap_or_default();
        ctx.send_viewport_cmd(egui::ViewportCommand::Title(format!(
            "pdf-view - {} - {}/{}",
            file_name,
            self.page + 1,
            self.page_count
        )));
    }
}

fn run() -> Result<(), String> {
    let args = parse_args()?;
    let (page_count, page_sizes) = document_info(&args.file)?;
    let title = format!("pdf-view - {}", args.file.display());
    let viewport = if let Some(placement) = args.placement {
        egui::ViewportBuilder::default()
            .with_position([placement.x as f32, placement.y as f32])
            .with_inner_size([placement.width as f32, placement.height as f32])
            .with_maximized(placement.maximized)
    } else {
        egui::ViewportBuilder::default().with_inner_size([DEFAULT_WIDTH, DEFAULT_HEIGHT])
    };
    let options = eframe::NativeOptions {
        viewport: viewport
            .with_min_inner_size([480.0, 360.0])
            .with_title(title),
        ..Default::default()
    };
    let viewer = PdfViewer::new(args.file, page_count, page_sizes);

    eframe::run_native(
        "pdf-view",
        options,
        Box::new(move |cc| {
            cc.egui_ctx.set_visuals(egui::Visuals::dark());
            Ok(Box::new(viewer))
        }),
    )
    .map_err(|error| format!("failed to open window: {error}"))
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("error: {error}");
            ExitCode::from(1)
        }
    }
}
