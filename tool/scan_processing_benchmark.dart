import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:windows_doc_capture/windows_doc_capture.dart';
import '../test/fixtures.dart';

void main() {
  test(
    'synthetic warp and full snapshot processing (not camera latency)',
    () async {
      final frame = fixture(width: 1280, height: 720);
      final source = img.Image.fromBytes(
        width: frame.width,
        height: frame.height,
        bytes: frame.rgba.buffer,
        numChannels: 4,
      );
      const q = [
        Offset(230, 130),
        Offset(1050, 140),
        Offset(1030, 590),
        Offset(240, 580),
      ];
      for (var i = 0; i < 3; i++) {
        warpPerspective(source, q);
      }
      final warp = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        final crop = warpPerspective(source, q);
        expect(crop.width, greaterThan(800));
      }
      warp.stop();
      await const CropPipeline().capture(frame);
      final capture = Stopwatch()..start();
      for (var i = 0; i < 3; i++) {
        expect(await const CropPipeline().capture(frame), isNotNull);
      }
      capture.stop();
      // ignore: avoid_print
      print(
        'PROCESSING_BENCHMARK os=${Platform.operatingSystem} mode=flutter-test size=1280x720 warp_mean_ms=${(warp.elapsedMicroseconds / 20000).toStringAsFixed(2)} capture_mean_ms=${(capture.elapsedMicroseconds / 3000).toStringAsFixed(2)}',
      );
    },
  );
}
