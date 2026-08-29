use std::env;
use std::io::Read;
use std::path::Path;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

#[cfg(windows)]
use std::ffi::OsStr;
#[cfg(windows)]
use std::os::windows::ffi::OsStrExt;

#[cfg(windows)]
use windows::core::PCWSTR;
#[cfg(windows)]
use windows::Win32::Foundation::GENERIC_READ;
#[cfg(windows)]
use windows::Win32::Graphics::Imaging::{
    CLSID_WICImagingFactory, GUID_WICPixelFormat32bppBGRA, IWICImagingFactory,
    WICBitmapDitherTypeNone, WICBitmapPaletteTypeCustom, WICDecodeMetadataCacheOnLoad,
};
#[cfg(windows)]
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CoUninitialize, CLSCTX_INPROC_SERVER, COINIT_MULTITHREADED,
};

use eframe::egui;
use egui::{
    Color32, ColorImage, Context, Rect, Sense, TextureHandle, TextureOptions, Vec2, ViewportCommand,
};
use image::{DynamicImage, GenericImageView, RgbaImage};
use viewer_window_placement::{WindowPlacement, ARGUMENT as WINDOW_PLACEMENT_ARGUMENT};

const DEFAULT_W: usize = 960;
const DEFAULT_H: usize = 720;
const MAX_MAGICK_DIMENSION: &str = "3200x3200>";

const RAW_EXTENSIONS: &[&str] = &[
    "3fr", "ari", "arw", "bay", "cap", "cr2", "cr3", "crw", "cs1", "dc2", "dcr", "dcs", "dng",
    "drf", "eip", "erf", "fff", "ia", "iiq", "k25", "kc2", "kdc", "mef", "mos", "mrw", "nef",
    "nkd", "nrw", "orf", "ori", "pef", "ptx", "pxn", "qtk", "raf", "raw", "rdc", "rw2", "rwl",
    "sr2", "srf", "srw", "sti", "x3f", "cine",
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
    } else if ext == "ptx" && looks_like_vflash_ptx(path) {
        load_vflash_ptx(path)
    } else if ext == "xface" {
        load_xface(path).or_else(|xface_error| {
            load_magick(path).map_err(|magick_error| {
                format!(
                    "X-Face decode failed: {xface_error}; ImageMagick fallback failed: {magick_error}"
                )
            })
        })
    } else if ext == "mvg" {
        // ImageMagick's MVG coder is available in the portable runtime, but
        // extension-based detection may reject local MVG files. Force the
        // coder so vector samples use the bundled renderer consistently.
        load_magick_with_format("mvg", path)
    } else if ext == "jng" {
        // Some JNG files contain a valid JPEG color stream but an alpha PNG
        // with a non-standard bit-depth marker. Keep the color preview when
        // ImageMagick cannot decode the combined JNG container.
        load_embedded_jpeg(path).or_else(|jpeg_error| {
            load_magick(path).map_err(|magick_error| {
                format!(
                    "embedded JPEG preview failed: {jpeg_error}; ImageMagick fallback failed: {magick_error}"
                )
            })
        })
    } else if ext == "jxr" {
        load_wic(path).or_else(|wic_error| {
            load_magick(path).map_err(|magick_error| {
                format!(
                    "Windows WIC decode failed: {wic_error}; ImageMagick fallback failed: {magick_error}"
                )
            })
        })
    } else if ext == "ora" {
        load_ora_thumbnail(path).or_else(|ora_error| {
            load_magick(path).map_err(|magick_error| {
                format!(
                    "OpenRaster thumbnail fallback failed: {ora_error}; ImageMagick fallback failed: {magick_error}"
                )
            })
        })
    } else if RAW_EXTENSIONS.contains(&ext.as_str()) {
        // LibRaw is substantially faster for camera containers. Keep
        // ImageMagick and content sniffing as fallbacks for formats that LibRaw
        // does not cover (including mislabeled images such as a JPEG named
        // `.raw`).
        load_libraw(path).or_else(|libraw_error| {
            load_magick(path).or_else(|magick_error| {
                load_magick_with_format("dng", path).or_else(|forced_magick_error| {
                    load_from_memory(path).or_else(|memory_error| {
                        load_embedded_jpeg(path).map_err(|preview_error| {
                            format!(
                                "LibRaw sidecar decode failed: {libraw_error}; ImageMagick RAW decode failed: {magick_error}; ImageMagick forced DNG/LibRaw decode failed: {forced_magick_error}; content decode failed: {memory_error}; embedded preview failed: {preview_error}"
                            )
                        })
                    })
                })
            })
        })
    } else {
        image::open(path).or_else(|image_error| {
            load_from_memory(path).or_else(|memory_error| {
                load_magick(path).map_err(|magick_error| {
                    format!(
                        "native image decoder failed: {image_error}; content decode failed: {memory_error}; ImageMagick fallback failed: {magick_error}"
                    )
                })
            })
        })
    }
}

fn load_from_memory(path: &str) -> Result<DynamicImage, String> {
    let data = std::fs::read(path).map_err(|error| format!("failed to read image: {error}"))?;
    image::load_from_memory(&data).map_err(|error| format!("content sniff failed: {error}"))
}

fn load_ora_thumbnail(path: &str) -> Result<DynamicImage, String> {
    let file = std::fs::File::open(path).map_err(|error| format!("failed to open ORA: {error}"))?;
    let mut archive = zip::ZipArchive::new(file)
        .map_err(|error| format!("invalid ORA ZIP container: {error}"))?;
    let mut errors = Vec::new();

    for name in [
        "Thumbnails/thumbnail.png",
        "Thumbnails/thumbnail.jpg",
        "data/mergedimage.png",
        "data/background.png",
    ] {
        let result = (|| {
            let mut entry = archive
                .by_name(name)
                .map_err(|error| format!("{name}: {error}"))?;
            let mut bytes = Vec::new();
            entry
                .read_to_end(&mut bytes)
                .map_err(|error| format!("{name}: failed to read entry: {error}"))?;
            image::load_from_memory(&bytes)
                .map_err(|error| format!("{name}: invalid image data: {error}"))
        })();
        match result {
            Ok(image) => return Ok(image),
            Err(error) => errors.push(error),
        }
    }

    Err(errors.join("; "))
}

#[cfg(windows)]
fn load_wic(path: &str) -> Result<DynamicImage, String> {
    let wide_path: Vec<u16> = OsStr::new(path).encode_wide().chain(Some(0)).collect();
    let init_result = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
    if init_result.is_err() && init_result.0 != 0x80010106u32 as i32 {
        return Err(format!(
            "COM initialization failed: 0x{:08x}",
            init_result.0
        ));
    }
    let uninitialize = init_result.is_ok();
    let result = (|| unsafe {
        let factory: IWICImagingFactory =
            CoCreateInstance(&CLSID_WICImagingFactory, None, CLSCTX_INPROC_SERVER)
                .map_err(|error| format!("WIC factory unavailable: {error}"))?;
        let decoder = factory
            .CreateDecoderFromFilename(
                PCWSTR(wide_path.as_ptr()),
                None,
                GENERIC_READ,
                WICDecodeMetadataCacheOnLoad,
            )
            .map_err(|error| format!("WIC decoder unavailable: {error}"))?;
        let frame = decoder
            .GetFrame(0)
            .map_err(|error| format!("WIC frame decode failed: {error}"))?;
        let converter = factory
            .CreateFormatConverter()
            .map_err(|error| format!("WIC format converter unavailable: {error}"))?;
        converter
            .Initialize(
                &frame,
                &GUID_WICPixelFormat32bppBGRA,
                WICBitmapDitherTypeNone,
                None,
                0.0,
                WICBitmapPaletteTypeCustom,
            )
            .map_err(|error| format!("WIC pixel conversion failed: {error}"))?;
        let mut width = 0u32;
        let mut height = 0u32;
        converter
            .GetSize(&mut width, &mut height)
            .map_err(|error| format!("WIC image dimensions unavailable: {error}"))?;
        let stride = width
            .checked_mul(4)
            .ok_or_else(|| "WIC image stride overflow".to_owned())?;
        let byte_count = (stride as usize)
            .checked_mul(height as usize)
            .ok_or_else(|| "WIC image size overflow".to_owned())?;
        let mut bgra = vec![0u8; byte_count];
        converter
            .CopyPixels(std::ptr::null(), stride, &mut bgra)
            .map_err(|error| format!("WIC pixel copy failed: {error}"))?;
        for pixel in bgra.chunks_exact_mut(4) {
            pixel.swap(0, 2);
        }
        RgbaImage::from_raw(width, height, bgra)
            .map(DynamicImage::ImageRgba8)
            .ok_or_else(|| "WIC returned an invalid pixel buffer".to_owned())
    })();
    if uninitialize {
        unsafe { CoUninitialize() };
    }
    result
}

#[cfg(not(windows))]
fn load_wic(_path: &str) -> Result<DynamicImage, String> {
    Err("Windows WIC is unavailable on this platform".to_owned())
}

// Some RAW containers carry a JPEG preview even when the bundled LibRaw build
// does not support that particular camera family. Decode the largest validated
// JPEG segment as a last-resort preview rather than treating arbitrary bytes as
// an image.
fn load_embedded_jpeg(path: &str) -> Result<DynamicImage, String> {
    let data = std::fs::read(path).map_err(|error| format!("failed to read RAW: {error}"))?;
    let mut cursor = 0usize;
    let mut best: Option<(u64, DynamicImage)> = None;

    while cursor + 1 < data.len() {
        let Some(relative_start) = data[cursor..]
            .windows(2)
            .position(|marker| marker == [0xff, 0xd8])
        else {
            break;
        };
        let start = cursor + relative_start;
        let Some(relative_end) = data[start + 2..]
            .windows(2)
            .position(|marker| marker == [0xff, 0xd9])
        else {
            break;
        };
        let end = start + 2 + relative_end + 2;
        if let Ok(image) = image::load_from_memory(&data[start..end]) {
            let area = u64::from(image.width()) * u64::from(image.height());
            if best
                .as_ref()
                .map_or(true, |(best_area, _)| area > *best_area)
            {
                best = Some((area, image));
            }
        }
        cursor = end;
    }

    best.map(|(_, image)| image)
        .ok_or_else(|| "no embedded JPEG preview found".to_owned())
}

fn read_u16_le(data: &[u8], offset: usize) -> Option<u16> {
    let bytes = data.get(offset..offset + 2)?;
    Some(u16::from_le_bytes([bytes[0], bytes[1]]))
}

fn looks_like_vflash_ptx(path: &str) -> bool {
    let Ok(data) = std::fs::read(path) else {
        return false;
    };
    let Some(offset) = read_u16_le(&data, 0) else {
        return false;
    };
    let Some(width) = read_u16_le(&data, 8) else {
        return false;
    };
    let Some(height) = read_u16_le(&data, 10) else {
        return false;
    };
    let Some(bits_per_pixel) = read_u16_le(&data, 12) else {
        return false;
    };
    let Some(pixel_bytes) = (width as usize)
        .checked_mul(height as usize)
        .and_then(|count| count.checked_mul(2))
    else {
        return false;
    };
    let Some(expected_size) = (offset as usize).checked_add(pixel_bytes) else {
        return false;
    };
    offset == 0x2c && width > 0 && height > 0 && bits_per_pixel == 16 && data.len() >= expected_size
}

fn load_vflash_ptx(path: &str) -> Result<DynamicImage, String> {
    let data = std::fs::read(path).map_err(|error| format!("failed to read PTX: {error}"))?;
    let offset = read_u16_le(&data, 0).ok_or_else(|| "PTX header is truncated".to_owned())?;
    let width = read_u16_le(&data, 8).ok_or_else(|| "PTX header is truncated".to_owned())?;
    let height = read_u16_le(&data, 10).ok_or_else(|| "PTX header is truncated".to_owned())?;
    let bits_per_pixel =
        read_u16_le(&data, 12).ok_or_else(|| "PTX header is truncated".to_owned())?;

    if offset != 0x2c || width == 0 || height == 0 || bits_per_pixel != 16 {
        return Err("unsupported PTX header (expected V.Flash 16-bit BGR555)".to_owned());
    }

    let pixel_count = (width as usize)
        .checked_mul(height as usize)
        .ok_or_else(|| "PTX dimensions overflow".to_owned())?;
    let data_size = pixel_count
        .checked_mul(2)
        .ok_or_else(|| "PTX dimensions overflow".to_owned())?;
    let pixels = data
        .get(offset as usize..offset as usize + data_size)
        .ok_or_else(|| "PTX pixel data is truncated".to_owned())?;

    let mut rgba = Vec::with_capacity(pixel_count * 4);
    for pair in pixels.chunks_exact(2) {
        let value = u16::from_le_bytes([pair[0], pair[1]]);
        let red = ((value >> 10) & 0x1f) as u8;
        let green = ((value >> 5) & 0x1f) as u8;
        let blue = (value & 0x1f) as u8;
        rgba.extend_from_slice(&[
            (red << 3) | (red >> 2),
            (green << 3) | (green >> 2),
            (blue << 3) | (blue >> 2),
            255,
        ]);
    }

    RgbaImage::from_raw(width as u32, height as u32, rgba)
        .map(DynamicImage::ImageRgba8)
        .ok_or_else(|| "failed to construct PTX image".to_owned())
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

fn magick_command(executable: &Path) -> Command {
    let mut command = Command::new(executable);
    if let Some(runtime_dir) = executable.parent() {
        // Keep ImageMagick isolated from machine-wide installations and their modules.
        command
            .env("MAGICK_HOME", runtime_dir)
            .env("MAGICK_CONFIGURE_PATH", runtime_dir)
            .env("MAGICK_CODER_MODULE_PATH", runtime_dir)
            .env("MAGICK_CODER_FILTER_MODULE_PATH", runtime_dir);
    }
    command
}

fn load_magick(path: &str) -> Result<DynamicImage, String> {
    load_magick_input(path)
}

fn load_magick_with_format(format: &str, path: &str) -> Result<DynamicImage, String> {
    load_magick_input(&format!("{format}:{path}"))
}

fn load_magick_input(input: &str) -> Result<DynamicImage, String> {
    let executable = runtime_executable("magick", "magick.exe")?;

    let output = magick_command(&executable)
        .arg(input)
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

// Decode camera/Phantom RAW containers with the bundled LibRaw sidecar. The
// executable remains isolated from the Flutter process and emits PPM bytes.
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

        let output = magick_command(&magick)
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
    use std::io::Cursor;
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT_TEST_FILE: AtomicU64 = AtomicU64::new(0);

    fn test_path(extension: &str) -> std::path::PathBuf {
        env::temp_dir().join(format!(
            "inf-dir-img-view-test-{}-{}-{extension}.{extension}",
            std::process::id(),
            NEXT_TEST_FILE.fetch_add(1, Ordering::Relaxed),
        ))
    }

    fn put_u16_le(data: &mut [u8], offset: usize, value: u16) {
        data[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
    }

    #[test]
    fn recognizes_raw_extensions() {
        assert!(RAW_EXTENSIONS.contains(&"cr2"));
        assert!(RAW_EXTENSIONS.contains(&"dng"));
        assert!(RAW_EXTENSIONS.contains(&"x3f"));
        assert!(RAW_EXTENSIONS.contains(&"cr3"));
        assert!(RAW_EXTENSIONS.contains(&"cine"));
    }

    #[test]
    fn decodes_vflash_ptx_bgr555() {
        let path = test_path("ptx");
        let mut data = vec![0u8; 44];
        put_u16_le(&mut data, 0, 0x2c);
        put_u16_le(&mut data, 8, 2);
        put_u16_le(&mut data, 10, 1);
        put_u16_le(&mut data, 12, 16);
        data.extend_from_slice(&0x7c00u16.to_le_bytes());
        data.extend_from_slice(&0x001fu16.to_le_bytes());
        std::fs::write(&path, data).expect("write PTX fixture");

        let image = load_image(path.to_str().expect("UTF-8 test path")).expect("decode PTX");
        assert_eq!(image.dimensions(), (2, 1));
        let rgba = image.to_rgba8();
        assert_eq!(rgba.get_pixel(0, 0).0, [255, 0, 0, 255]);
        assert_eq!(rgba.get_pixel(1, 0).0, [0, 0, 255, 255]);
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn does_not_treat_tiff_ptx_as_vflash() {
        let path = test_path("ptx");
        std::fs::write(&path, b"II*\0").expect("write TIFF header");
        assert!(!looks_like_vflash_ptx(
            path.to_str().expect("UTF-8 test path")
        ));
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn decodes_content_when_extension_is_mislabeled() {
        let path = test_path("raw");
        let source = RgbaImage::from_pixel(1, 1, image::Rgba([12, 34, 56, 255]));
        let mut encoded = Cursor::new(Vec::new());
        DynamicImage::ImageRgba8(source)
            .write_to(&mut encoded, image::ImageFormat::Png)
            .expect("encode PNG fixture");
        std::fs::write(&path, encoded.into_inner()).expect("write mislabeled fixture");

        let image = load_image(path.to_str().expect("UTF-8 test path")).expect("decode content");
        assert_eq!(image.to_rgba8().get_pixel(0, 0).0, [12, 34, 56, 255]);
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn decodes_largest_embedded_jpeg_preview() {
        let path = test_path("x3f");
        let mut small_encoded = Cursor::new(Vec::new());
        DynamicImage::ImageRgba8(RgbaImage::from_pixel(1, 1, image::Rgba([20, 30, 40, 255])))
            .write_to(&mut small_encoded, image::ImageFormat::Jpeg)
            .expect("encode small JPEG fixture");
        let mut large_encoded = Cursor::new(Vec::new());
        DynamicImage::ImageRgba8(RgbaImage::from_pixel(2, 1, image::Rgba([80, 90, 100, 255])))
            .write_to(&mut large_encoded, image::ImageFormat::Jpeg)
            .expect("encode large JPEG fixture");
        let mut container = b"X3F container".to_vec();
        container.extend_from_slice(&small_encoded.into_inner());
        container.extend_from_slice(b"metadata");
        container.extend_from_slice(&large_encoded.into_inner());
        container.extend_from_slice(b"trailer");
        std::fs::write(&path, container).expect("write X3F fixture");

        let image = load_embedded_jpeg(path.to_str().expect("UTF-8 test path"))
            .expect("decode embedded JPEG");
        assert_eq!(image.dimensions(), (2, 1));
        let _ = std::fs::remove_file(path);
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
