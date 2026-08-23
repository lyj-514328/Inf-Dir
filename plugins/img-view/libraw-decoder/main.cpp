// libraw-decoder: decode a camera RAW file to an 8-bit sRGB PPM stream on
// stdout, using LibRaw's dcraw processing pipeline. Runs as a sidecar
// process spawned by img-view (never loaded into the Flutter main process).
//
// Usage: libraw-decoder.exe <image>
// Exit:  0 on success (PPM P6 on stdout), non-zero on failure (stderr).

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#if defined(_WIN32)
#include <fcntl.h>
#include <io.h>
#endif

#include "libraw/libraw.h"

namespace {

constexpr int kMaxDimension = 3200;

void fail(const char* what, int rc) {
  std::fprintf(stderr, "LibRaw %s failed: %s\n", what, libraw_strerror(rc));
}

// Box-average downscale so the largest edge is at most kMaxDimension.
std::vector<unsigned char> shrink(const unsigned char* src, int width, int height, int step) {
  const int out_w = (width + step - 1) / step;
  const int out_h = (height + step - 1) / step;
  std::vector<unsigned char> out(static_cast<size_t>(out_w) * out_h * 3);
  for (int y = 0; y < out_h; ++y) {
    for (int x = 0; x < out_w; ++x) {
      int sum[3] = {0, 0, 0};
      int count = 0;
      const int y0 = y * step;
      const int x0 = x * step;
      for (int dy = 0; dy < step && y0 + dy < height; ++dy) {
        const int row = (y0 + dy) * width;
        for (int dx = 0; dx < step && x0 + dx < width; ++dx) {
          const int idx = (row + x0 + dx) * 3;
          sum[0] += src[idx];
          sum[1] += src[idx + 1];
          sum[2] += src[idx + 2];
          ++count;
        }
      }
      const int dst = (y * out_w + x) * 3;
      for (int c = 0; c < 3; ++c) {
        out[dst + c] = static_cast<unsigned char>(sum[c] / count);
      }
    }
  }
  return out;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::fprintf(stderr, "Usage: libraw-decoder.exe <image>\n");
    return 2;
  }

#if defined(_WIN32)
  // Keep stdout in binary mode: otherwise the CRT translates every \n (also
  // inside pixel data) to \r\n and corrupts the PPM stream.
  _setmode(_fileno(stdout), _O_BINARY);
#endif

  LibRaw raw;
  int rc = raw.open_file(argv[1]);
  if (rc != LIBRAW_SUCCESS) {
    fail("open_file", rc);
    return 1;
  }
  rc = raw.unpack();
  if (rc != LIBRAW_SUCCESS) {
    fail("unpack", rc);
    return 1;
  }

  raw.imgdata.params.output_bps = 8;
  raw.imgdata.params.output_color = 1;  // sRGB
  raw.imgdata.params.use_camera_wb = 1;
  rc = raw.dcraw_process();
  if (rc != LIBRAW_SUCCESS) {
    fail("dcraw_process", rc);
    return 1;
  }

  libraw_processed_image_t* image = raw.dcraw_make_mem_image(&rc);
  if (image == nullptr || rc != LIBRAW_SUCCESS) {
    fail("dcraw_make_mem_image", rc);
    return 1;
  }

  int result = 1;
  if (image->type != LIBRAW_IMAGE_BITMAP || image->colors != 3) {
    std::fprintf(stderr, "LibRaw returned unsupported image (type=%d colors=%d)\n",
                 image->type, image->colors);
  } else {
    const int width = static_cast<int>(image->width);
    const int height = static_cast<int>(image->height);
    const int step = std::max(1, (std::max(width, height) + kMaxDimension - 1) / kMaxDimension);
    const unsigned char* pixels = image->data;
    bool downscaled = false;
    std::vector<unsigned char> scaled;
    if (step > 1) {
      scaled = shrink(pixels, width, height, step);
      pixels = scaled.data();
    }
    (void)downscaled;
    // PPM P6.
    const std::string header =
        "P6\n" + std::to_string(width / step + ((width % step) ? 1 : 0)) + " " +
        std::to_string(height / step + ((height % step) ? 1 : 0)) + "\n255\n";
    if (std::fwrite(header.data(), 1, header.size(), stdout) != header.size()) {
      std::fprintf(stderr, "failed to write PPM header\n");
    } else {
      const size_t data_size = static_cast<size_t>(width / step + ((width % step) ? 1 : 0)) *
                               (height / step + ((height % step) ? 1 : 0)) * 3;
      const size_t written =
          std::fwrite(pixels, 1, data_size, stdout);
      result = (written == data_size) ? 0 : 1;
      if (result != 0) {
        std::fprintf(stderr, "failed to write PPM pixels (%zu/%zu)\n", written, data_size);
      }
    }
  }

  libraw_dcraw_clear_mem(image);
  return result;
}
