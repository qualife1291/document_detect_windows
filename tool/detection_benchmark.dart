import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import '../test/fixtures.dart';

void main() {
  test(
    'synthetic 640px detection benchmark (not native preview latency)',
    () async {
      final detector = PureDartDocumentDetector();
      final frames = List.generate(
        5,
        (i) =>
            fixture(width: 640, height: 480, paper: 170 + i * 10, sequence: i),
      );
      for (final frame in frames) {
        await detector.detect(frame);
      }
      final times = <int>[];
      for (var i = 0; i < 30; i++) {
        final watch = Stopwatch()..start();
        final result = await detector.detect(frames[i % frames.length]);
        expect(result.hasDocument, isTrue);
        times.add(watch.elapsedMicroseconds);
      }
      times.sort();
      final mean = times.reduce((a, b) => a + b) / times.length;
      // ignore: avoid_print
      print(
        'BENCHMARK os=${Platform.operatingSystem} mode=flutter-test synthetic=30 size=640x480 mean_ms=${(mean / 1000).toStringAsFixed(2)} p95_ms=${(times[28] / 1000).toStringAsFixed(2)} fps=${(1e6 / mean).toStringAsFixed(2)}',
      );
      if (const bool.fromEnvironment('ENFORCE_TARGET_FPS')) {
        expect(
          1e6 / mean,
          greaterThanOrEqualTo(10),
          reason: 'Target kiosk detection must sustain 10 FPS',
        );
      }
      detector.dispose();
    },
  );
}
