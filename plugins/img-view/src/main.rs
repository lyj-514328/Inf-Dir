use std::env;
use std::path::Path;

use image::{DynamicImage, GenericImageView, ImageBuffer, Rgba};
use image::imageops;
use minifb::{Key, MouseButton, MouseMode, Window, WindowOptions};

/// Helper: pack Rgba pixel into the u32 0RGB format that minifb expects.
#[inline(always)]
fn pack_rgb(pixel: Rgba<u8>) -> u32 {
    (pixel[0] as u32) << 16 | (pixel[1] as u32) << 8 | pixel[2] as u32
}

// ---------------------------------------------------------------------------
// Viewer state
// ---------------------------------------------------------------------------

/// 默认 Quick View 窗口尺寸（Windows 上 Q-Dir / TC 风格预览的典型值）。
const DEFAULT_W: usize = 960;
const DEFAULT_H: usize = 720;

struct Viewer {
    // Source data
    original: DynamicImage,   // as-loaded from disk
    rotated: DynamicImage,    // post-rotation cache

    // View parameters
    zoom: f32,                // 1.0 = 100 %
    offset_x: f32,            // horizontal pan offset (pixels, in scaled space)
    offset_y: f32,            // vertical   pan offset
    rotation: u8,             // 0-3 (each step = 90° clockwise)
    fit: bool,                // fit-to-window mode (overrides zoom)

    // Drag state
    dragging: bool,
    drag_ox: f32,
    drag_oy: f32,

    // Window
    window: Window,
    buf: Vec<u32>,
}

impl Viewer {
    /// `win_w` / `win_h` = 0 表示使用默认尺寸。
    fn new(filepath: &str, win_w: usize, win_h: usize) -> Result<Self, Box<dyn std::error::Error>> {
        let original = image::open(filepath)?;
        let (img_w, img_h) = original.dimensions();

        let win_w = if win_w > 0 {
            win_w
        } else {
            // 默认尺寸：取图片宽度与 DEFAULT_W 的较小值，但不超过 1280
            (img_w as usize).min(DEFAULT_W).max(640)
        };
        let win_h = if win_h > 0 {
            win_h
        } else {
            (img_h as usize).min(DEFAULT_H).max(480)
        };

        let window = Window::new(
            &format!("img-view — {}", filepath),
            win_w,
            win_h,
            WindowOptions {
                resize: true,
                ..WindowOptions::default()
            },
        )?;

        let buf = vec![0u32; win_w * win_h];

        Ok(Viewer {
            rotated: original.clone(),
            original,
            zoom: 1.0,
            offset_x: 0.0,
            offset_y: 0.0,
            rotation: 0,
            fit: true,
            dragging: false,
            drag_ox: 0.0,
            drag_oy: 0.0,
            window,
            buf,
        })
    }

    /// Re-compute `rotated` from `original` (cheap).
    fn apply_rotation(&mut self) {
        self.rotated = match self.rotation % 4 {
            1 => self.original.rotate90(),
            2 => self.original.rotate180(),
            3 => self.original.rotate270(),
            _ => self.original.clone(),
        };
    }

    // -----------------------------------------------------------------------
    // Rendering
    // -----------------------------------------------------------------------

    fn render(&mut self) {
        let (win_w, win_h) = self.window.get_size();
        let n = win_w * win_h;
        if self.buf.len() != n {
            self.buf.resize(n, 0);
        }

        let (img_w, img_h) = self.rotated.dimensions();

        // ----- display size -----
        let (disp_w, disp_h) = if self.fit {
            let scale =
                (win_w as f32 / img_w as f32).min(win_h as f32 / img_h as f32);
            (
                (img_w as f32 * scale).round() as u32,
                (img_h as f32 * scale).round() as u32,
            )
        } else {
            (
                (img_w as f32 * self.zoom).round() as u32,
                (img_h as f32 * self.zoom).round() as u32,
            )
        };

        // Only re-scale when something relevant changed.
        // We cache the most recent scaled buffer to avoid re-scaling on every
        // pan-only frame.  For simplicity in v1 we just scale every frame
        // (imageops::resize with Nearest is very fast).
        let scaled_buf: ImageBuffer<Rgba<u8>, Vec<u8>> = self
            .rotated
            .resize_exact(
                disp_w.max(1),
                disp_h.max(1),
                imageops::FilterType::Nearest,
            )
            .to_rgba8();

        // ----- centering and pan -----
        let cx = (win_w as i32 - disp_w as i32).max(0) as u32 / 2;
        let cy = (win_h as i32 - disp_h as i32).max(0) as u32 / 2;

        let max_ox = (disp_w as i32 - win_w as i32).max(0) as f32;
        let max_oy = (disp_h as i32 - win_h as i32).max(0) as f32;
        let ox = self.offset_x.clamp(0.0, max_ox) as i32;
        let oy = self.offset_y.clamp(0.0, max_oy) as i32;

        // ----- fill window buffer -----
        self.buf.fill(0);
        for wy in 0..win_h {
            for wx in 0..win_w {
                let ix = wx as i32 - cx as i32 + ox;
                let iy = wy as i32 - cy as i32 + oy;
                if ix >= 0 && iy >= 0 && ix < disp_w as i32 && iy < disp_h as i32
                {
                    self.buf[wy * win_w + wx] =
                        pack_rgb(*scaled_buf.get_pixel(ix as u32, iy as u32));
                }
            }
        }

        // ----- title bar -----
        let info = if self.fit {
            let s = (win_w as f32 / img_w as f32).min(win_h as f32 / img_h as f32);
            format!("img-view [{:.0}% fit]", s * 100.0)
        } else {
            format!("img-view [{:.0}%]", self.zoom * 100.0)
        };
        self.window.set_title(&info);

        self.window
            .update_with_buffer(&self.buf, win_w, win_h)
            .unwrap();
    }

    // -----------------------------------------------------------------------
    // Input
    // -----------------------------------------------------------------------

    fn handle_input(&mut self) {
        // ----- zoom (key repeat OK — system repeat rate is comfortable) -----
        if self.window.is_key_pressed(Key::Equal, minifb::KeyRepeat::Yes)
            || self.window.is_key_pressed(Key::NumPadPlus, minifb::KeyRepeat::Yes)
        {
            self.fit = false;
            self.zoom = (self.zoom * 1.15).min(32.0);
        }
        if self.window.is_key_pressed(Key::Minus, minifb::KeyRepeat::Yes)
            || self.window
                .is_key_pressed(Key::NumPadMinus, minifb::KeyRepeat::Yes)
        {
            self.fit = false;
            self.zoom = (self.zoom / 1.15).max(0.02);
        }

        // ----- mouse wheel -----
        if let Some((_, dy)) = self.window.get_scroll_wheel() {
            self.fit = false;
            if dy > 0.0 {
                self.zoom = (self.zoom * 1.15).min(32.0);
            } else if dy < 0.0 {
                self.zoom = (self.zoom / 1.15).max(0.02);
            }
        }

        // ----- one-shot keys -----
        if self.window.is_key_pressed(Key::F, minifb::KeyRepeat::No) {
            self.fit = true;
            self.offset_x = 0.0;
            self.offset_y = 0.0;
        }
        if self.window.is_key_pressed(Key::O, minifb::KeyRepeat::No) {
            self.fit = false;
            self.zoom = 1.0;
            self.offset_x = 0.0;
            self.offset_y = 0.0;
        }
        if self.window.is_key_pressed(Key::R, minifb::KeyRepeat::No) {
            self.rotation = (self.rotation + 1) % 4;
            self.apply_rotation();
            self.offset_x = 0.0;
            self.offset_y = 0.0;
        }

        // ----- pan with mouse drag -----
        let left_down = self.window.get_mouse_down(MouseButton::Left);
        if left_down {
            if let Some((mx, my)) = self.window.get_mouse_pos(MouseMode::Clamp) {
                if !self.dragging {
                    self.dragging = true;
                    self.drag_ox = mx;
                    self.drag_oy = my;
                } else {
                    let (win_w, win_h) = self.window.get_size();
                    let (img_w, img_h) = self.rotated.dimensions();

                    let (disp_w, disp_h) = if self.fit {
                        let s = (win_w as f32 / img_w as f32)
                            .min(win_h as f32 / img_h as f32);
                        (
                            (img_w as f32 * s) as u32,
                            (img_h as f32 * s) as u32,
                        )
                    } else {
                        (
                            (img_w as f32 * self.zoom) as u32,
                            (img_h as f32 * self.zoom) as u32,
                        )
                    };

                    let max_ox = (disp_w as i32 - win_w as i32).max(0) as f32;
                    self.offset_x = (self.offset_x - (mx - self.drag_ox))
                        .clamp(0.0, max_ox);

                    let max_oy = (disp_h as i32 - win_h as i32).max(0) as f32;
                    self.offset_y = (self.offset_y - (my - self.drag_oy))
                        .clamp(0.0, max_oy);

                    self.drag_ox = mx;
                    self.drag_oy = my;
                }
            }
        } else {
            self.dragging = false;
        }
    }

    // -----------------------------------------------------------------------
    // Main loop
    // -----------------------------------------------------------------------

    fn run(&mut self) {
        while self.window.is_open() && !self.window.is_key_down(Key::Escape) {
            self.handle_input();
            self.render();
        }
    }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();

    // 解析参数：img-view <FILE> [WIDTH] [HEIGHT]
    let mut file_arg: Option<&str> = None;
    let mut win_w: usize = 0;
    let mut win_h: usize = 0;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--width" | "-w" if i + 1 < args.len() => {
                win_w = args[i + 1].parse().unwrap_or(0);
                i += 2;
            }
            "--height" | "-h" if i + 1 < args.len() => {
                win_h = args[i + 1].parse().unwrap_or(0);
                i += 2;
            }
            s if s.starts_with('-') => {
                eprintln!("Unknown option: {}", s);
                std::process::exit(1);
            }
            _ => {
                file_arg = Some(&args[i]);
                i += 1;
            }
        }
    }

    let path = file_arg.unwrap_or_else(|| {
        eprintln!("Usage: img-view <IMAGE_FILE> [--width W] [--height H]");
        std::process::exit(1);
    });

    if !Path::new(path).exists() {
        eprintln!("Error: file not found — {}", path);
        std::process::exit(1);
    }

    let mut viewer = Viewer::new(path, win_w, win_h)?;
    viewer.run();
    Ok(())
}
