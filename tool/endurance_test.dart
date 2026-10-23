import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import '../test/document_conditions_test.dart' show documentScene;

/// Synthetic pipeline exercise; not a substitute for a physical-camera soak.
/// flutter test tool/endurance_test.dart --dart-define=SOAK_SECONDS=86400
void main() {
  const seconds = int.fromEnvironment('SOAK_SECONDS', defaultValue: 60);
  test('bounded analysis under continuous burst load', () async {
    final analyzer = DocumentQualityAnalyzer(maxWidth: 320);
    final frame = documentScene(width: 320, height: 240);
    var sequence = 0, reports = 0, peakRss = ProcessInfo.currentRss;
    final rss = <int>[];
    final clock = Stopwatch()..start();
    Completer<void>? finished;
    final sub = analyzer.reports.listen((report) {
      reports++;
      if (report.sequence == sequence && !(finished?.isCompleted ?? true)) {
        finished!.complete();
      }
    });
    await analyzer.start();
    try {
      while (clock.elapsed < Duration(seconds: seconds)) {
        finished = Completer<void>();
        for (var burst = 0; burst < 30; burst++) {
          analyzer.add(
            FrameBuffer(
              width: frame.width,
              height: frame.height,
              rgba: frame.rgba,
              capturedAt: DateTime.now(),
              sequence: ++sequence,
            ),
          );
          expect(analyzer.pendingFrames, lessThanOrEqualTo(1));
        }
        await finished.future.timeout(const Duration(seconds: 5));
        final memory = ProcessInfo.currentRss;
        if (memory > peakRss) peakRss = memory;
        if (rss.length <= clock.elapsed.inSeconds ~/ 5) rss.add(memory);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    } finally {
      await sub.cancel();
      await analyzer.dispose();
    }
    expect(reports, greaterThan(0));
    expect(analyzer.pendingFrames, 0);
    // Keep measurements, not an unportable GC/RSS threshold from a hosted VM.
    // No pixels, document text, file paths or identity data in diagnostics.
    // ignore: avoid_print
    print(
      'ENDURANCE ${jsonEncode({'platform': Platform.operatingSystem, 'seconds': clock.elapsed.inSeconds, 'offered': sequence, 'reports': reports, 'dropped': analyzer.droppedFrames, 'peak_rss_bytes': peakRss, 'rss_samples': rss})}',
    );
  }, timeout: Timeout(Duration(seconds: seconds + 60)));
}
