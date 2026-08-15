use std::env;
use std::path::Path;

use eframe::egui;
use egui::{
    Color32, ColorImage, Context, Rect, Sense, TextureHandle, TextureOptions, Vec2, ViewportCommand,
};
use image::{DynamicImage, GenericImageView};
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};

const DEFAULT_W: usize = 960;
const DEFAULT_H: usize = 720;

fn color_image(img: &DynamicImage) -> ColorImage {
    let rgba = img.to_rgba8();
    let size = [rgba.width() as usize, rgba.height() as usize];
    ColorImage::from_rgba_unmultiplied(size, rgba.as_raw())
}

struct Viewer {
    original: DynamicImage,
    rotated: DynamicImage,
    texture: TextureHandle,
    rotation: u8,
    zoom: f32,
    offset: Vec2,
    fit: bool,
}

impl Viewer {
    fn new(cc: &eframe::CreationContext<'_>, original: DynamicImage) -> Self {
        let rotated = original.clone();
        let texture =
            cc.egui_ctx
                .load_texture("img", color_image(&rotated), TextureOptions::LINEAR);
        Viewer {
            original,
            rotated,
            texture,
            rotation: 0,
            zoom: 1.0,
            offset: Vec2::ZERO,
            fit: true,
        }
    }

    fn apply_rotation(&mut self, ctx: &Context) {
        self.rotated = match self.rotation % 4 {
            1 => self.original.rotate90(),
            2 => self.original.rotate180(),
            3 => self.original.rotate270(),
            _ => self.original.clone(),
        };
        self.texture = ctx.load_texture("img", color_image(&self.rotated), TextureOptions::LINEAR);
    }

    fn apply_zoom(&mut self, factor: f32, pivot: Vec2) {
        let new_zoom = (self.zoom * factor).clamp(0.02, 32.0);
        let actual = new_zoom / self.zoom;
        self.offset = pivot - (pivot - self.offset) * actual;
        self.zoom = new_zoom;
    }
}

impl eframe::App for Viewer {
    fn update(&mut self, ctx: &Context, _frame: &mut eframe::Frame) {
        if ctx.input(|i| i.key_pressed(egui::Key::Escape)) {
            ctx.send_viewport_cmd(ViewportCommand::Close);
            return;
        }
        if ctx.input(|i| i.key_pressed(egui::Key::F)) {
            self.fit = true;
            self.offset = Vec2::ZERO;
        }
        if ctx.input(|i| i.key_pressed(egui::Key::O)) {
            self.fit = false;
            self.zoom = 1.0;
            self.offset = Vec2::ZERO;
        }
        if ctx.input(|i| i.key_pressed(egui::Key::R)) {
            self.rotation = (self.rotation + 1) % 4;
            self.apply_rotation(ctx);
            self.offset = Vec2::ZERO;
        }

        egui::CentralPanel::default().show(ctx, |ui| {
            let available = ui.available_rect_before_wrap();
            let avail = available.size();
            let (iw, ih) = self.rotated.dimensions();
            let img = Vec2::new(iw as f32, ih as f32);
            let fit_scale = (avail.x / img.x).min(avail.y / img.y);
            let center = available.center();

            let response = ui.allocate_rect(available, Sense::drag());

            let mut key_factor = 1.0f32;
            if ctx.input(|i| i.key_pressed(egui::Key::Equals) || i.key_pressed(egui::Key::Plus)) {
                key_factor *= 1.15;
            }
            if ctx.input(|i| i.key_pressed(egui::Key::Minus)) {
                key_factor /= 1.15;
            }
            if key_factor != 1.0 {
                if self.fit {
                    self.zoom = fit_scale;
                    self.fit = false;
                }
                self.apply_zoom(key_factor, Vec2::ZERO);
            }

            let scroll = ctx.input(|i| i.raw_scroll_delta.y);
            if scroll != 0.0 {
                if self.fit {
                    self.zoom = fit_scale;
                    self.fit = false;
                }
                let factor = if scroll > 0.0 { 1.15 } else { 1.0 / 1.15 };
                let pivot = response
                    .hover_pos()
                    .map(|p| p - center)
                    .unwrap_or(Vec2::ZERO);
                self.apply_zoom(factor, pivot);
            }

            if response.dragged() {
                self.offset += response.drag_delta();
            }

            let scale = if self.fit { fit_scale } else { self.zoom };
            let disp = img * scale;

            let max_x = ((disp.x - avail.x) * 0.5).max(0.0);
            let max_y = ((disp.y - avail.y) * 0.5).max(0.0);
            self.offset.x = self.offset.x.clamp(-max_x, max_x);
            self.offset.y = self.offset.y.clamp(-max_y, max_y);

            ui.painter().rect_filled(available, 0.0, Color32::BLACK);
            let rect = Rect::from_center_size(center + self.offset, disp);
            let uv = Rect::from_min_max(egui::pos2(0.0, 0.0), egui::pos2(1.0, 1.0));
            ui.painter()
                .image(self.texture.id(), rect, uv, Color32::WHITE);

            let title = if self.fit {
                format!("img-view [{:.0}% fit]", scale * 100.0)
            } else {
                format!("img-view [{:.0}%]", scale * 100.0)
            };
            ctx.send_viewport_cmd(ViewportCommand::Title(title));
        });
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();

    let mut file_arg: Option<&str> = None;
    let mut placement: Option<WindowPlacement> = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            WINDOW_PLACEMENT_ARGUMENT => {
                let value = args.get(i + 1).unwrap_or_else(|| {
                    eprintln!("{WINDOW_PLACEMENT_ARGUMENT} requires a JSON value");
                    std::process::exit(1);
                });
                let parsed = WindowPlacement::from_json(value).unwrap_or_else(|error| {
                    eprintln!("{error}");
                    std::process::exit(1);
                });
                if placement.replace(parsed).is_some() {
                    eprintln!("{WINDOW_PLACEMENT_ARGUMENT} may only be specified once");
                    std::process::exit(1);
                }
                i += 2;
            }
            s if s.starts_with('-') => {
                eprintln!("Unknown option: {}", s);
                std::process::exit(1);
            }
            _ => {
                if file_arg.is_some() {
                    eprintln!("Unexpected argument: {}", args[i]);
                    std::process::exit(1);
                }
                file_arg = Some(&args[i]);
                i += 1;
            }
        }
    }

    let path = file_arg.unwrap_or_else(|| {
        eprintln!("Usage: img-view <IMAGE_FILE> [{WINDOW_PLACEMENT_ARGUMENT} JSON]");
        std::process::exit(1);
    });

    if !Path::new(path).exists() {
        eprintln!("Error: file not found — {}", path);
        std::process::exit(1);
    }

    let original = match image::open(path) {
        Ok(img) => img,
        Err(e) => {
            eprintln!("Error: failed to load image — {}", e);
            std::process::exit(1);
        }
    };

    let (iw, ih) = original.dimensions();
    let viewport = if let Some(placement) = placement {
        egui::ViewportBuilder::default()
            .with_position([placement.x as f32, placement.y as f32])
            .with_inner_size([
                placement.client_width as f32,
                placement.client_height as f32,
            ])
            .with_maximized(placement.maximized)
    } else {
        let win_w = (iw as usize).min(DEFAULT_W).max(640);
        let win_h = (ih as usize).min(DEFAULT_H).max(480);
        egui::ViewportBuilder::default().with_inner_size([win_w as f32, win_h as f32])
    };

    let native_options = eframe::NativeOptions {
        viewport: viewport.with_title("img-view"),
        ..Default::default()
    };

    if let Err(e) = eframe::run_native(
        "img-view",
        native_options,
        Box::new(move |cc| Ok(Box::new(Viewer::new(cc, original)))),
    ) {
        eprintln!("Error: failed to open window — {}", e);
        std::process::exit(1);
    }
}
