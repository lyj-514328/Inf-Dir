use std::env;
use std::path::Path;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use eframe::egui;
use egui::{
    Color32, ColorImage, Context, Rect, Sense, TextureHandle, TextureOptions, Vec2, ViewportCommand,
};
use image::{DynamicImage, GenericImageView};
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};

const DEFAULT_W: usize = 960;
const DEFAULT_H: usize = 720;
const MAX_MAGICK_DIMENSION: &str = "3200x3200>";

const RAW_EXTENSIONS: &[&str] = &[
    "ari", "arw", "cr2", "cr3", "crw", "dcr", "dcs", "dng", "erf", "iiq", "k25", "kdc", "mef", "mos",
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
    } else if ext == "xface" {
        load_xface(path).or_else(|xface_error| {
            load_magick(path).map_err(|magick_error| {
                format!(
                    "X-Face decode failed: {xface_error}; ImageMagick fallback failed: {magick_error}"
                )
            })
        })
    } else if RAW_EXTENSIONS.contains(&ext.as_str()) {
        load_libraw(path).or_else(|libraw_error| {
            load_wic(path).or_else(|wic_error| load_magick(path).map_err(|magick_error| {
                format!(
                    "LibRaw RAW decode failed: {libraw_error}; WIC fallback failed: {wic_error}; ImageMagick fallback failed: {magick_error}"
                )
            }))
        })
    } else {
        image::open(path).or_else(|image_error| {
            load_wic(path).or_else(|wic_error| load_magick(path).map_err(|magick_error| {
                format!(
                    "native image decoder failed: {image_error}; WIC fallback failed: {wic_error}; ImageMagick fallback failed: {magick_error}"
                )
            }))
        })
    }
}

fn runtime_executable(directory: &str, executable: &str) -> Result<std::path::PathBuf, String> {
    let path = env::current_exe()
        .map_err(|error| error.to_string())?
        .parent()
        .map(|parent| parent.join(directory).join(executable))
        .ok_or_else(|| "image-view executable has no parent directory".to_owned())?;
    if !path.is_file() {
        return Err(format!("runtime is missing: {}", path.display()));
    }
    Ok(path)
}

fn load_magick(path: &str) -> Result<DynamicImage, String> {
    let executable = runtime_executable("magick", "magick.exe")?;

    let output = Command::new(&executable)
        .arg(path)
        .arg("-auto-orient")
        .arg("-resize")
        .arg(MAX_MAGICK_DIMENSION)
        .arg("png:-")
        .output()
        .map_err(|error| format!("failed to start {}: {error}", executable.display()))?;
    if !output.status.success() {
        let detail = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        return Err(if detail.is_empty() {
            format!("ImageMagick exited with {}", output.status)
        } else {
            detail
        });
    }
    image::load_from_memory(&output.stdout)
        .map_err(|error| format!("ImageMagick returned invalid PNG: {error}"))
}

// Decode a camera RAW file with the libraw-decoder sidecar (LibRaw 0.22.2
// dcraw pipeline) which emits a PPM stream on stdout.
fn load_libraw(path: &str) -> Result<DynamicImage, String> {
    let executable = runtime_executable("libraw-decoder", "libraw-decoder.exe")?;
    let output = Command::new(&executable)
        .arg(path)
        .output()
        .map_err(|error| format!("failed to start {}: {error}", executable.display()))?;
    if !output.status.success() {
        let detail = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        return Err(if detail.is_empty() {
            format!("LibRaw decoder exited with {}", output.status)
        } else {
            detail
        });
    }
    image::load_from_memory(&output.stdout)
        .map_err(|error| format!("LibRaw decoder returned invalid image: {error}"))
}

fn load_wic(path: &str) -> Result<DynamicImage, String> {
    let executable = runtime_executable("wic-decoder", "wic-decoder.exe")?;
    let output = Command::new(&executable)
        .arg(path)
        .output()
        .map_err(|error| format!("failed to start {}: {error}", executable.display()))?;
    if !output.status.success() {
        let detail = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        return Err(if detail.is_empty() {
            format!("WIC decoder exited with {}", output.status)
        } else {
            detail
        });
    }
    image::load_from_memory(&output.stdout)
        .map_err(|error| format!("WIC decoder returned invalid PNG: {error}"))
}

fn load_xface(path: &str) -> Result<DynamicImage, String> {
    let uncompface = runtime_executable("compface", "uncompface.exe")?;
    let magick = runtime_executable("magick", "magick.exe")?;
    let mut input =
        std::fs::read(path).map_err(|error| format!("failed to read X-Face: {error}"))?;
    if input
        .get(..7)
        .is_some_and(|prefix| prefix.eq_ignore_ascii_case(b"X-Face:"))
    {
        input = input[7..].to_vec();
    }

    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_nanos();
    let temp = env::temp_dir()
        .join("Inf-Dir")
        .join("img-view")
        .join(format!("xface-{}-{nonce}", std::process::id()));
    std::fs::create_dir_all(&temp)
        .map_err(|error| format!("failed to create X-Face temp directory: {error}"))?;

    let result = (|| {
        let source = temp.join("source.xface");
        let xbm = temp.join("source.xbm");
        std::fs::write(&source, input)
            .map_err(|error| format!("failed to stage X-Face data: {error}"))?;
        let expanded = Command::new(&uncompface)
            .arg("-X")
            .arg(&source)
            .arg(&xbm)
            .output()
            .map_err(|error| format!("failed to start uncompface: {error}"))?;
        if !expanded.status.success() {
            return Err(String::from_utf8_lossy(&expanded.stderr).trim().to_string());
        }

        let output = Command::new(&magick)
            .arg(&xbm)
            .args(["-resize", MAX_MAGICK_DIMENSION, "png:-"])
            .output()
            .map_err(|error| format!("failed to start ImageMagick: {error}"))?;
        if !output.status.success() {
            return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
        }
        image::load_from_memory(&output.stdout)
            .map_err(|error| format!("ImageMagick returned invalid X-Face PNG: {error}"))
    })();
    let _ = std::fs::remove_dir_all(temp);
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recognizes_raw_extensions() {
        assert!(RAW_EXTENSIONS.contains(&"cr2"));
        assert!(RAW_EXTENSIONS.contains(&"dng"));
        assert!(RAW_EXTENSIONS.contains(&"x3f"));
        assert!(RAW_EXTENSIONS.contains(&"cr3"));
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
        eprintln!("Error: file not found 鈥?{}", path);
        std::process::exit(1);
    }

    let original = match load_image(path) {
        Ok(img) => img,
        Err(e) => {
            eprintln!("Error: failed to load image 鈥?{}", e);
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
        eprintln!("Error: failed to open window 鈥?{}", e);
        std::process::exit(1);
    }
}
