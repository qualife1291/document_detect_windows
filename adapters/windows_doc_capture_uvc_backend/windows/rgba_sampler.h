// Bounded, allocation-free RGBA sampling. No Windows/Flutter dependency.
#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace doc_capture {
struct SampleSize { int width = 0; int height = 0; };
inline SampleSize FitSize(int width, int height, int maximum) {
  if (width < 2 || height < 2 || width > 8192 || height > 8192 || maximum < 2 || maximum > 1280 ||
      static_cast<int64_t>(width) * height > 9000000) return {};
  const double scale = std::min(1.0, static_cast<double>(maximum) /
                                       std::max(width, height));
  return {std::max(2, static_cast<int>(std::round(width * scale))),
          std::max(2, static_cast<int>(std::round(height * scale)))};
}
inline bool SampleRgba(const uint8_t* source, size_t source_length,
                       int width, int height, uint8_t* output,
                       size_t capacity, int maximum, bool interpolate,
                       SampleSize* result) {
  const auto size = FitSize(width, height, maximum);
  if (!result || !source || !output || size.width == 0 ||
      source_length < static_cast<size_t>(width) * height * 4 ||
      capacity < static_cast<size_t>(size.width) * size.height * 4) return false;
  const bool linear = interpolate && (width != size.width || height != size.height);
  std::array<int, 1280> x_offsets{}, x_next{}, x_weights{};
  for (int x = 0; x < size.width; ++x) {
    if (linear) {
      const double sx = std::max(0.0, (x + .5) * width / size.width - .5);
      const int x0 = static_cast<int>(sx);
      x_offsets[x] = x0 * 4;
      x_next[x] = std::min(width - 1, x0 + 1) * 4;
      x_weights[x] = static_cast<int>((sx - x0) * 256);
    } else {
      x_offsets[x] = x * width / size.width * 4;
    }
  }
  for (int y = 0; y < size.height; ++y) {
    const double sy = std::max(0.0, (y + .5) * height / size.height - .5);
    const int y0 = linear ? static_cast<int>(sy) : y * height / size.height;
    const int y1 = std::min(height - 1, y0 + 1);
    const int fy = static_cast<int>((sy - y0) * 256);
    const auto row0 = source + static_cast<size_t>(y0) * width * 4;
    const auto row1 = source + static_cast<size_t>(y1) * width * 4;
    auto dest = output + static_cast<size_t>(y) * size.width * 4;
    for (int x = 0; x < size.width; ++x, dest += 4) {
      const auto a = row0 + x_offsets[x];
      if (!linear) {
        dest[0] = a[0]; dest[1] = a[1]; dest[2] = a[2];
      } else {
        const auto b = row0 + x_next[x];
        const auto c = row1 + x_offsets[x];
        const auto d = row1 + x_next[x];
        const int fx = x_weights[x];
        for (int ch = 0; ch < 3; ++ch) {
          const int top = a[ch] * (256 - fx) + b[ch] * fx;
          const int bottom = c[ch] * (256 - fx) + d[ch] * fx;
          dest[ch] = static_cast<uint8_t>((top * (256 - fy) + bottom * fy + 32768) >> 16);
        }
      }
      dest[3] = 255;
    }
  }
  *result = size;
  return true;
}
}  // namespace doc_capture
