import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('JPEG detail/size/time tradeoff on synthetic fine print', () {
    final source = img.Image(width: 1280, height: 720);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final ink = y % 24 < 12 && x % 11 < 3;
        final v = ink ? 28 : 232 + (x + y) % 16;
        source.setPixelRgb(x, y, v, v, v);
      }
    }
    for (final quality in [90, 92, 95]) {
      img.encodeJpg(source, quality: quality); // warm up separately
      final watch = Stopwatch()..start();
      final bytes = img.encodeJpg(source, quality: quality);
      watch.stop();
      final decoded = img.decodeJpg(bytes)!;
      double error = 0;
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          final diff = source.getPixel(x, y).r - decoded.getPixel(x, y).r;
          error += diff * diff;
        }
      }
      error /= source.width * source.height;
      expect(decoded.width, source.width);
      expect(error, lessThan(10));
      // ignore: avoid_print
      print(
        'JPEG_BENCHMARK os=${Platform.operatingSystem} synthetic=true quality=$quality bytes=${bytes.length} encode_ms=${watch.elapsedMilliseconds} luma_mse=${error.toStringAsFixed(4)}',
      );
    }
  });
}
