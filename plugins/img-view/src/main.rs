use std::env;
use std::path::Path;

use eframe::egui;
use egui::{
    Color32, ColorImage, Context, Rect, Sense, TextureHandle, TextureOptions, Vec2, ViewportCommand,
};
use image::{DynamicImage, GenericImageView, RgbImage};
use rawloader::{Orientation, RawImage, RawImageData};
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};

const DEFAULT_W: usize = 960;
const DEFAULT_H: usize = 720;
const MAX_RAW_DIMENSION: usize = 3200;

const RAW_EXTENSIONS: &[&str] = &[
    "ari", "arw", "cr2", "crw", "dcr", "dcs", "dng", "erf", "iiq", "k25", "kdc", "mef", "mos",
    "mrw", "nef", "nkd", "nrw", "orf", "pef", "raf", "raw", "rw2", "sr2", "srf", "srw", "x3f",
];

fn color_image(img: &DynamicImage) -> ColorImage {
    let rgba = img.to_rgba8();
    let size = [rgba.width() as usize, rgba.height() as usize];
    ColorImage::from_rgba_unmultiplied(size, rgba.as_raw())
}

fn load_image(path: &str) -> Result<DynamicImage, String> {
    let ext = Path::new(path)
        .extension()
        .map(|e| e.to_string_lossy().to_ascii_lowercase())
        .unwrap_or_default();

    if ext == "svg" || ext == "svgz" {
        load_svg(path)
    } else if RAW_EXTENSIONS.contains(&ext.as_str()) {
        load_raw(path)
    } else {
        image::open(path).map_err(|e| e.to_string())
    }
}

fn load_raw(path: &str) -> Result<DynamicImage, String> {
    let raw =
        rawloader::decode_file(path).map_err(|error| format!("RAW decode failed: {error}"))?;
    let image = raw_to_rgb(&raw)?;
    Ok(apply_orientation(image, raw.orientation))
}

fn raw_to_rgb(raw: &RawImage) -> Result<DynamicImage, String> {
    if raw.width == 0 || raw.height == 0 {
        return Err("RAW image has an invalid size".to_owned());
    }

    let step = raw.width.max(raw.height).div_ceil(MAX_RAW_DIMENSION).max(1);
    let output_width = raw.width.div_ceil(step) as u32;
    let output_height = raw.height.div_ceil(step) as u32;

    let image = match &raw.data {
        RawImageData::Integer(data) => {
            if raw.cpp >= 3 {
                rgb_integer_image(raw, data, step, output_width, output_height)?
            } else {
                bayer_integer_image(raw, data, step, output_width, output_height)?
            }
        }
        RawImageData::Float(data) => {
            if raw.cpp >= 3 {
                rgb_float_image(raw, data, step, output_width, output_height)?
            } else {
                bayer_float_image(raw, data, step, output_width, output_height)?
            }
        }
    };

    Ok(DynamicImage::ImageRgb8(image))
}

fn rgb_integer_image(
    raw: &RawImage,
    data: &[u16],
    step: usize,
    width: u32,
    height: u32,
) -> Result<RgbImage, String> {
    expected_data_len(raw, data.len())?;
    let mut output = RgbImage::new(width, height);
    for (x, y, pixel) in output.enumerate_pixels_mut() {
        let source_x = (x as usize * step).min(raw.width - 1);
        let source_y = (y as usize * step).min(raw.height - 1);
        let offset = (source_y * raw.width + source_x) * raw.cpp;
        for channel in 0..3 {
            let value = data[offset + channel];
            pixel[channel] = scale_integer(
                value,
                raw.blacklevels[channel],
                raw.whitelevels[channel],
                raw.wb_coeffs[channel],
            );
        }
    }
    Ok(output)
}

fn rgb_float_image(
    raw: &RawImage,
    data: &[f32],
    step: usize,
    width: u32,
    height: u32,
) -> Result<RgbImage, String> {
    expected_data_len(raw, data.len())?;
    let mut output = RgbImage::new(width, height);
    for (x, y, pixel) in output.enumerate_pixels_mut() {
        let source_x = (x as usize * step).min(raw.width - 1);
        let source_y = (y as usize * step).min(raw.height - 1);
        let offset = (source_y * raw.width + source_x) * raw.cpp;
        for channel in 0..3 {
            pixel[channel] = scale_float(data[offset + channel], raw.wb_coeffs[channel]);
        }
    }
    Ok(output)
}

fn bayer_integer_image(
    raw: &RawImage,
    data: &[u16],
    step: usize,
    width: u32,
    height: u32,
) -> Result<RgbImage, String> {
    expected_data_len(raw, data.len())?;
    let mut output = RgbImage::new(width, height);
    for (x, y, pixel) in output.enumerate_pixels_mut() {
        let source_x = (x as usize * step).min(raw.width - 1);
        let source_y = (y as usize * step).min(raw.height - 1);
        for channel in 0..3 {
            let value = sample_bayer_integer(raw, data, source_x, source_y, channel);
            pixel[channel] = (value * 255.0).round().clamp(0.0, 255.0) as u8;
        }
    }
    Ok(output)
}

fn bayer_float_image(
    raw: &RawImage,
    data: &[f32],
    step: usize,
    width: u32,
    height: u32,
) -> Result<RgbImage, String> {
    expected_data_len(raw, data.len())?;
    let mut output = RgbImage::new(width, height);
    for (x, y, pixel) in output.enumerate_pixels_mut() {
        let source_x = (x as usize * step).min(raw.width - 1);
        let source_y = (y as usize * step).min(raw.height - 1);
        for channel in 0..3 {
            let value = sample_bayer_float(raw, data, source_x, source_y, channel);
            pixel[channel] = (value * 255.0).round().clamp(0.0, 255.0) as u8;
        }
    }
    Ok(output)
}

fn expected_data_len(raw: &RawImage, actual: usize) -> Result<(), String> {
    let expected = raw
        .width
        .checked_mul(raw.height)
        .and_then(|size| size.checked_mul(raw.cpp))
        .ok_or_else(|| "RAW image dimensions overflow".to_owned())?;
    if actual < expected {
        return Err(format!(
            "RAW pixel data is truncated (expected {expected}, got {actual})"
        ));
    }
    Ok(())
}

fn scale_integer(value: u16, black: u16, white: u16, wb: f32) -> u8 {
    let range = white.saturating_sub(black).max(1) as f32;
    let normalized = ((value.saturating_sub(black) as f32) / range) * wb.max(0.01);
    (normalized.clamp(0.0, 1.0) * 255.0).round() as u8
}

fn scale_float(value: f32, wb: f32) -> u8 {
    let normalized = if value > 1.0 { value / 65535.0 } else { value };
    (normalized * wb.max(0.01))
        .clamp(0.0, 1.0)
        .mul_add(255.0, 0.0)
        .round() as u8
}

fn sample_bayer_integer(raw: &RawImage, data: &[u16], x: usize, y: usize, target: usize) -> f32 {
    let mut total = 0.0;
    let mut weight = 0.0;
    for radius in 0..=2 {
        let min_y = y.saturating_sub(radius);
        let max_y = (y + radius).min(raw.height - 1);
        let min_x = x.saturating_sub(radius);
        let max_x = (x + radius).min(raw.width - 1);
        for row in min_y..=max_y {
            for col in min_x..=max_x {
                if raw.cfa.color_at(row, col) != target {
                    continue;
                }
                let distance = ((row as isize - y as isize).unsigned_abs()
                    + (col as isize - x as isize).unsigned_abs())
                    as f32;
                let current_weight = 1.0 / (1.0 + distance);
                let offset = row * raw.width + col;
                let value = ((data[offset].saturating_sub(raw.blacklevels[target]) as f32)
                    / raw.whitelevels[target]
                        .saturating_sub(raw.blacklevels[target])
                        .max(1) as f32)
                    * raw.wb_coeffs[target].max(0.01);
                total += value * current_weight;
                weight += current_weight;
            }
        }
        if weight > 0.0 {
            break;
        }
    }
    if weight == 0.0 {
        0.0
    } else {
        (total / weight).clamp(0.0, 1.0)
    }
}

fn sample_bayer_float(raw: &RawImage, data: &[f32], x: usize, y: usize, target: usize) -> f32 {
    let mut total = 0.0;
    let mut weight = 0.0;
    for radius in 0..=2 {
        let min_y = y.saturating_sub(radius);
        let max_y = (y + radius).min(raw.height - 1);
        let min_x = x.saturating_sub(radius);
        let max_x = (x + radius).min(raw.width - 1);
        for row in min_y..=max_y {
            for col in min_x..=max_x {
                if raw.cfa.color_at(row, col) != target {
                    continue;
                }
                let distance = ((row as isize - y as isize).unsigned_abs()
                    + (col as isize - x as isize).unsigned_abs())
                    as f32;
                let current_weight = 1.0 / (1.0 + distance);
                let value = if data[row * raw.width + col] > 1.0 {
                    data[row * raw.width + col] / 65535.0
                } else {
                    data[row * raw.width + col]
                } * raw.wb_coeffs[target].max(0.01);
                total += value * current_weight;
                weight += current_weight;
            }
        }
        if weight > 0.0 {
            break;
        }
    }
    if weight == 0.0 {
        0.0
    } else {
        (total / weight).clamp(0.0, 1.0)
    }
}

fn apply_orientation(image: DynamicImage, orientation: Orientation) -> DynamicImage {
    let (transpose, horizontal, vertical) = orientation.to_flips();
    let mut output = image;
    if horizontal {
        output = output.fliph();
    }
    if vertical {
        output = output.flipv();
    }
    if transpose {
        output = output.rotate90();
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recognizes_raw_extensions() {
        assert!(RAW_EXTENSIONS.contains(&"cr2"));
        assert!(RAW_EXTENSIONS.contains(&"dng"));
        assert!(RAW_EXTENSIONS.contains(&"x3f"));
        assert!(!RAW_EXTENSIONS.contains(&"cr3"));
    }

    #[test]
    fn scales_integer_sensor_values() {
        assert_eq!(scale_integer(512, 0, 1023, 1.0), 128);
        assert_eq!(scale_integer(0, 128, 1023, 1.0), 0);
        assert_eq!(scale_integer(1023, 0, 1023, 1.0), 255);
    }

    #[test]
    fn preserves_orientation_dimensions() {
        let image = DynamicImage::ImageRgb8(RgbImage::new(4, 2));
        assert_eq!(
            apply_orientation(image.clone(), Orientation::Normal).dimensions(),
            (4, 2)
        );
        assert_eq!(
            apply_orientation(image, Orientation::Rotate90).dimensions(),
            (2, 4)
        );
    }
}

fn load_svg(path: &str) -> Result<DynamicImage, String> {
    let svg_data = std::fs::read(path).map_err(|e| e.to_string())?;

    let opt = {
        let mut opt = resvg::usvg::Options {
            resources_dir: Path::new(path).parent().map(|p| p.to_path_buf()),
            ..resvg::usvg::Options::default()
        };
        opt.fontdb_mut().load_system_fonts();
        opt
    };

    let tree = resvg::usvg::Tree::from_data(&svg_data, &opt).map_err(|e| e.to_string())?;

    let pixmap_size = tree.size().to_int_size();
    let mut pixmap = resvg::tiny_skia::Pixmap::new(pixmap_size.width(), pixmap_size.height())
        .ok_or_else(|| "invalid SVG size".to_owned())?;

    resvg::render(
        &tree,
        resvg::tiny_skia::Transform::default(),
        &mut pixmap.as_mut(),
    );

    let (w, h) = (pixmap.width(), pixmap.height());
    let rgba = image::RgbaImage::from_raw(w, h, pixmap.data().to_vec())
        .ok_or_else(|| "failed to convert SVG pixels".to_owned())?;
    Ok(DynamicImage::ImageRgba8(rgba))
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

    let original = match load_image(path) {
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
