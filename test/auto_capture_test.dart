import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'fixtures.dart';

void main() {
  test('requires eight stable frames and visible 500ms feedback', () {
    final c = AutoCaptureController();
    for (var i = 0; i < 7; i++) {
      expect(
        c.update(good(), normalized, Duration(milliseconds: i * 100)),
        isFalse,
      );
    }
    expect(c.state, AutoCaptureState.stable);
    expect(c.feedbackProgress, 1);
    expect(
      c.update(good(), normalized, const Duration(milliseconds: 700)),
      isTrue,
    );
    expect(c.state, AutoCaptureState.capturing);
  });
  test('fast frame count alone never skips feedback', () {
    final c = AutoCaptureController(stableFrameCount: 2);
    for (var i = 0; i < 20; i++) {
      expect(
        c.update(good(), normalized, Duration(milliseconds: i * 10)),
        isFalse,
      );
    }
    expect(
      c.update(good(), normalized, const Duration(milliseconds: 510)),
      isTrue,
    );
  });
  test('motion accumulates relative to stable anchor and resets counter', () {
    final c = AutoCaptureController();
    for (var i = 0; i < 7; i++) {
      expect(
        c.update(good(), normalized, Duration(milliseconds: i * 100)),
        isFalse,
      );
    }
    final moved = normalized.map((p) => p + const Offset(.025, 0)).toList();
    expect(c.update(good(), moved, const Duration(milliseconds: 700)), isFalse);
    expect(c.stableFrames, 1);
  });
  test('bad quality, missing frame and time gaps reset stability', () {
    final c = AutoCaptureController();
    c.update(good(), normalized, Duration.zero);
    c.update(DetectionResult.empty(), null, const Duration(milliseconds: 100));
    expect(c.stableFrames, 0);
    c.update(good(), normalized, const Duration(milliseconds: 200));
    c.update(good(), normalized, const Duration(seconds: 2));
    expect(c.stableFrames, 1);
  });
  test('cooldown requires paper removal before a second auto capture', () {
    final c = AutoCaptureController();
    c.captureCompleted(Duration.zero);
    expect(c.update(good(), normalized, const Duration(seconds: 3)), isFalse);
    expect(c.state, AutoCaptureState.cooldown);
    c.update(DetectionResult.empty(), null, const Duration(seconds: 4));
    expect(
      c.update(good(), normalized, const Duration(milliseconds: 4100)),
      isFalse,
    );
    expect(c.state, AutoCaptureState.stable);
  });
  test('invalid feedback interval rejected', () {
    expect(
      () => AutoCaptureController(
        feedbackDuration: const Duration(milliseconds: 499),
      ),
      throwsArgumentError,
    );
  });
  test('warning metadata and severity are accessible and bounded', () {
    final r = DetectionResult(
      hasDocument: true,
      quad: good().quad,
      coverageRatio: .01,
      edgeMargin: 0,
      blurScore: 0,
      tiltAngle: 40,
      brightnessScore: .99,
      clippingRatio: 1,
    );
    final w = const QualityThresholds().warningsFor(r);
    expect(
      w.map((w) => w.type),
      containsAll([
        WarningType.outOfFrame,
        WarningType.blur,
        WarningType.tilt,
        WarningType.tooBright,
      ]),
    );
    for (final warning in w) {
      expect(warning.message, isNotEmpty);
      expect(warning.severity, inInclusiveRange(0, 1));
    }
  });
}
