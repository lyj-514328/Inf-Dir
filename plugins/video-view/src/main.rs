use std::env;
use std::ffi::{c_char, c_int, c_void, CString};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use eframe::egui;
use egui::{Color32, ColorImage, Context, Rect, Sense, TextureHandle, TextureOptions, Vec2, ViewportCommand};
use libmpv2::Mpv;

const DEFAULT_W: usize = 960;
const DEFAULT_H: usize = 540;
const RENDER_W: i32 = 1280;
const RENDER_H: i32 = 720;

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
enum MpvRenderParamType {
    Invalid = 0,
    ApiType = 1,
    AdvancedControl = 10,
    SwSize = 17,
    SwFormat = 18,
    SwStride = 19,
    SwPtr = 20,
}

#[repr(C)]
union MpvRenderParamValue {
    int: c_int,
    ptr: *mut c_void,
}

#[repr(C)]
struct MpvRenderParam {
    param_type: MpvRenderParamType,
    value: MpvRenderParamValue,
}

const MPV_RENDER_API_TYPE_SW: &str = "sw\0";

extern "C" {
    fn mpv_command_async(ctx: *mut c_void, reply_userdata: u64, args: *const *const c_char) -> c_int;

    fn mpv_render_context_create(
        res: *mut *mut c_void,
        mpv: *mut c_void,
        params: *const MpvRenderParam,
    ) -> c_int;

    fn mpv_render_context_update(ctx: *mut c_void) -> u64;

    fn mpv_render_context_render(
        ctx: *mut c_void,
        params: *mut MpvRenderParam,
    ) -> c_int;

    fn mpv_render_context_report_swap(ctx: *mut c_void);

    fn mpv_render_context_free(ctx: *mut c_void);

    fn mpv_render_context_set_update_callback(
        ctx: *mut c_void,
        callback: Option<unsafe extern "C" fn(cb_ctx: *mut c_void)>,
        cb_ctx: *mut c_void,
    );
}

unsafe extern "C" fn update_callback(cb_ctx: *mut c_void) {
    let flag = &*(cb_ctx as *const AtomicBool);
    flag.store(true, Ordering::Relaxed);
}

struct VideoViewer {
    mpv: Mpv,
    render_ctx: *mut c_void,
    frame_buf: Vec<u8>,
    texture: Option<TextureHandle>,
    frame_w: usize,
    frame_h: usize,
    needs_update: Arc<AtomicBool>,
    paused: bool,
    file_name: String,
}

unsafe impl Send for VideoViewer {}

impl VideoViewer {
    fn new(
        _cc: &eframe::CreationContext<'_>,
        mpv: Mpv,
        render_ctx: *mut c_void,
        needs_update: Arc<AtomicBool>,
        file_name: String,
    ) -> Self {
        let frame_w = RENDER_W as usize;
        let frame_h = RENDER_H as usize;
        let frame_buf = vec![0u8; frame_w * frame_h * 4];

        VideoViewer {
            mpv,
            render_ctx,
            frame_buf,
            texture: None,
            frame_w,
            frame_h,
            needs_update,
            paused: false,
            file_name,
        }
    }

    fn render_frame(&mut self, ctx: &Context) {
        let stride = (self.frame_w * 4) as i64;
        let size: [i32; 2] = [self.frame_w as i32, self.frame_h as i32];

        let mut params = [
            MpvRenderParam {
                param_type: MpvRenderParamType::SwSize,
                value: MpvRenderParamValue {
                    ptr: size.as_ptr() as *mut c_void,
                },
            },
            MpvRenderParam {
                param_type: MpvRenderParamType::SwFormat,
                value: MpvRenderParamValue {
                    ptr: b"rgb0\0".as_ptr() as *mut c_void,
                },
            },
            MpvRenderParam {
                param_type: MpvRenderParamType::SwStride,
                value: MpvRenderParamValue {
                    ptr: &stride as *const i64 as *mut c_void,
                },
            },
            MpvRenderParam {
                param_type: MpvRenderParamType::SwPtr,
                value: MpvRenderParamValue {
                    ptr: self.frame_buf.as_mut_ptr() as *mut c_void,
                },
            },
            MpvRenderParam {
                param_type: MpvRenderParamType::Invalid,
                value: MpvRenderParamValue { int: 0 },
            },
        ];

        let err = unsafe { mpv_render_context_render(self.render_ctx, params.as_mut_ptr()) };
        if err < 0 {
            return;
        }

        unsafe { mpv_render_context_report_swap(self.render_ctx) };

        for px in self.frame_buf.chunks_exact_mut(4) {
            px[3] = 255;
        }

        let image = ColorImage::from_rgba_unmultiplied(
            [self.frame_w, self.frame_h],
            &self.frame_buf,
        );

        match &mut self.texture {
            Some(tex) => tex.set(image, TextureOptions::LINEAR),
            None => {
                self.texture =
                    Some(ctx.load_texture("video", image, TextureOptions::LINEAR));
            }
        }
    }

    fn get_time_pos(&self) -> f64 {
        self.mpv
            .get_property::<f64>("time-pos")
            .unwrap_or(0.0)
    }

    fn get_duration(&self) -> f64 {
        self.mpv
            .get_property::<f64>("duration")
            .unwrap_or(0.0)
    }
}

impl eframe::App for VideoViewer {
    fn update(&mut self, ctx: &Context, _frame: &mut eframe::Frame) {
        if ctx.input(|i| i.key_pressed(egui::Key::Escape)) {
            ctx.send_viewport_cmd(ViewportCommand::Close);
            return;
        }

        if ctx.input(|i| i.key_pressed(egui::Key::Space)) {
            self.paused = !self.paused;
            let _ = self.mpv.set_property("pause", self.paused);
        }

        if ctx.input(|i| i.key_pressed(egui::Key::ArrowRight)) {
            let _ = self.mpv.command("seek", &["5", "relative"]);
        }
        if ctx.input(|i| i.key_pressed(egui::Key::ArrowLeft)) {
            let _ = self.mpv.command("seek", &["-5", "relative"]);
        }
        if ctx.input(|i| i.key_pressed(egui::Key::ArrowUp)) {
            let _ = self.mpv.command("seek", &["30", "relative"]);
        }
        if ctx.input(|i| i.key_pressed(egui::Key::ArrowDown)) {
            let _ = self.mpv.command("seek", &["-30", "relative"]);
        }

        let has_update = self.needs_update.swap(false, Ordering::Relaxed);
        if has_update {
            let flags = unsafe { mpv_render_context_update(self.render_ctx) };
            if flags & 1 != 0 {
                self.render_frame(ctx);
            }
            ctx.request_repaint();
        } else if !self.paused {
            ctx.request_repaint();
        }

        egui::TopBottomPanel::bottom("controls").show(ctx, |ui| {
            let pos = self.get_time_pos();
            let dur = self.get_duration();

            ui.horizontal(|ui| {
                if ui.button(if self.paused { "▶" } else { "⏸" }).clicked() {
                    self.paused = !self.paused;
                    let _ = self.mpv.set_property("pause", self.paused);
                }

                let fmt_time = |t: f64| {
                    let s = t as u64;
                    format!("{:02}:{:02}:{:02}", s / 3600, (s % 3600) / 60, s % 60)
                };

                ui.label(fmt_time(pos));

                let mut slider_val = pos as f32;
                if dur > 0.0 {
                    ui.add_sized(
                        [200.0, 20.0],
                        egui::Slider::new(&mut slider_val, 0.0..=dur as f32)
                            .show_value(false),
                    );
                    if slider_val as f64 != pos && (slider_val as f64 - pos).abs() > 1.0 {
                        let _ = self
                            .mpv
                            .command("seek", &[&format!("{}", slider_val), "absolute"]);
                    }
                }

                ui.label(fmt_time(dur));
            });
        });

        egui::CentralPanel::default().show(ctx, |ui| {
            let available = ui.available_rect_before_wrap();
            let avail = available.size();
            let center = available.center();

            let response = ui.allocate_rect(available, Sense::hover());
            let _ = response;

            ui.painter()
                .rect_filled(available, 0.0, Color32::BLACK);

            if let Some(tex) = &self.texture {
                let img = Vec2::new(self.frame_w as f32, self.frame_h as f32);
                let scale = (avail.x / img.x).min(avail.y / img.y);
                let disp = img * scale;
                let rect = Rect::from_center_size(center, disp);
                let uv = Rect::from_min_max(egui::pos2(0.0, 0.0), egui::pos2(1.0, 1.0));
                ui.painter()
                    .image(tex.id(), rect, uv, Color32::WHITE);
            }

            let title = format!("video-view — {}", self.file_name);
            ctx.send_viewport_cmd(ViewportCommand::Title(title));
        });
    }
}

impl Drop for VideoViewer {
    fn drop(&mut self) {
        if !self.render_ctx.is_null() {
            unsafe { mpv_render_context_free(self.render_ctx) };
            self.render_ctx = std::ptr::null_mut();
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();

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
        eprintln!("Usage: video-view <VIDEO_FILE> [--width W] [--height H]");
        std::process::exit(1);
    });

    if !Path::new(path).exists() {
        eprintln!("Error: file not found — {}", path);
        std::process::exit(1);
    }

    let file_name = Path::new(path)
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| path.to_string());

    let mpv = match Mpv::with_initializer(|init| {
        init.set_option("vo", "libmpv")?;
        init.set_option("hwdec", "auto")?;
        init.set_option("keep-open", "yes")?;
        init.set_option("idle", "yes")?;
        Ok(())
    }) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("Error: failed to create mpv instance — {:?}", e);
            std::process::exit(1);
        }
    };

    let raw_handle = mpv.ctx.as_ptr() as *mut c_void;

    let api_type_str = MPV_RENDER_API_TYPE_SW.as_ptr() as *mut c_void;
    let mut advanced: c_int = 1;
    let params = [
        MpvRenderParam {
            param_type: MpvRenderParamType::ApiType,
            value: MpvRenderParamValue { ptr: api_type_str },
        },
        MpvRenderParam {
            param_type: MpvRenderParamType::AdvancedControl,
            value: MpvRenderParamValue { ptr: &mut advanced as *mut c_int as *mut c_void },
        },
        MpvRenderParam {
            param_type: MpvRenderParamType::Invalid,
            value: MpvRenderParamValue { int: 0 },
        },
    ];

    let mut render_ctx: *mut c_void = std::ptr::null_mut();
    let err = unsafe { mpv_render_context_create(&mut render_ctx, raw_handle, params.as_ptr()) };
    if err < 0 {
        eprintln!("Error: failed to create render context (code {})", err);
        std::process::exit(1);
    }

    let needs_update = Arc::new(AtomicBool::new(true));
    let cb_ptr = Arc::as_ptr(&needs_update) as *mut c_void;
    unsafe {
        mpv_render_context_set_update_callback(render_ctx, Some(update_callback), cb_ptr);
    }

    {
        let cmd_loadfile = CString::new("loadfile").unwrap();
        let cmd_path = CString::new(path).unwrap();
        let args: [*const c_char; 3] = [
            cmd_loadfile.as_ptr(),
            cmd_path.as_ptr(),
            std::ptr::null(),
        ];
        let err = unsafe { mpv_command_async(raw_handle, 0, args.as_ptr()) };
        if err < 0 {
            eprintln!("Error: failed to load file (code {})", err);
            std::process::exit(1);
        }
    }

    let win_w = if win_w > 0 { win_w } else { DEFAULT_W };
    let win_h = if win_h > 0 { win_h } else { DEFAULT_H };

    let native_options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([win_w as f32, win_h as f32])
            .with_title("video-view"),
        ..Default::default()
    };

    if let Err(e) = eframe::run_native(
        "video-view",
        native_options,
        Box::new(move |cc| {
            Ok(Box::new(VideoViewer::new(cc, mpv, render_ctx, needs_update, file_name)))
        }),
    ) {
        eprintln!("Error: failed to open window — {}", e);
        std::process::exit(1);
    }
}
