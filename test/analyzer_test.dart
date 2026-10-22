import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'fixtures.dart';

void main() {
  test(
    'persistent isolate processes active then newest pending frame',
    () async {
      final analyzer = DocumentQualityAnalyzer();
      await analyzer.start();
      final reports = <QualityReport>[];
      final done = Completer<void>();
      final sub = analyzer.reports.listen((r) {
        reports.add(r);
        if (r.sequence == 20) done.complete();
      });
      final source = fixture();
      for (var i = 0; i <= 20; i++) {
        analyzer.add(
          FrameBuffer(
            width: source.width,
            height: source.height,
            rgba: source.rgba,
            capturedAt: DateTime.now(),
            sequence: i,
          ),
        );
        expect(analyzer.pendingFrames, lessThanOrEqualTo(1));
      }
      await done.future.timeout(const Duration(seconds: 10));
      expect(reports.map((r) => r.sequence), [0, 20]);
      expect(analyzer.droppedFrames, 19);
      expect(reports.last.result.hasDocument, isTrue);
      await sub.cancel();
      await analyzer.dispose();
      await analyzer.dispose();
    },
  );
}
