import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Original is the default for IDs and color-sensitive documents. Other modes
/// are explicit presentation choices, not OCR or restoration of missing detail.
enum DocumentImageFilter { original, enhance, grayscale }

img.Image filterDocument(img.Image image, DocumentImageFilter filter) {
  if (filter == DocumentImageFilter.original) return image;
  final data = image.data! as img.ImageDataUint8;
  final bytes = data.data, channels = image.numChannels;
  final histogram = Uint32List(256);
  if (filter == DocumentImageFilter.enhance) {
    for (var i = 0; i < bytes.length; i += channels) {
      histogram[(77 * bytes[i] + 150 * bytes[i + 1] + 29 * bytes[i + 2]) >>
          8]++;
    }
  }
  var low = 0, high = 255;
  if (filter == DocumentImageFilter.enhance) {
    var count = 0;
    final tail = image.width * image.height * .02;
    for (var i = 0; i < 256; i++) {
      count += histogram[i];
      if (count > tail) {
        low = i;
        break;
      }
    }
    count = 0;
    for (var i = 255; i >= 0; i--) {
      count += histogram[i];
      if (count > tail) {
        high = i;
        break;
      }
    }
    // Never amplify a blank/noisy document into artificial detail.
    if (high - low < 32) return image;
  }
  final gain = (255 / (high - low)).clamp(1.0, 1.5);
  for (var i = 0; i < bytes.length; i += channels) {
    if (filter == DocumentImageFilter.grayscale) {
      final value =
          (77 * bytes[i] + 150 * bytes[i + 1] + 29 * bytes[i + 2]) >> 8;
      bytes[i] = bytes[i + 1] = bytes[i + 2] = value;
    } else {
      for (var c = 0; c < 3; c++) {
        bytes[i + c] = ((bytes[i + c] - low) * gain).round().clamp(0, 255);
      }
    }
  }
  return image;
}
