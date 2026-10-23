import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'controller_test.dart' show FakeSource;
import 'fixtures.dart';

Future<DocumentPreviewStatus> analyzeFrame(
  WindowsDocCapture capture,
  FakeSource source,
  FrameBuffer frame,
) async {
  final done = Completer<DocumentPreviewStatus>();
  void listener() {
    final value = capture.currentPreviewStatus;
    if (value.report?.sequence == frame.sequence && !done.isCompleted) {
      done.complete(value);
    }
  }

  capture.previewStatus.addListener(listener);
  try {
    source.stream.add(frame);
    return await done.future.timeout(const Duration(seconds: 10));
  } finally {
    capture.previewStatus.removeListener(listener);
  }
}

Future<void> waitForPreviewState(
  WindowsDocCapture capture,
  DocumentPreviewState state,
) async {
  if (capture.currentPreviewStatus.state == state) return;
  final done = Completer<void>();
  void listener() {
    if (capture.currentPreviewStatus.state == state && !done.isCompleted) {
      done.complete();
    }
  }

  capture.previewStatus.addListener(listener);
  try {
    await done.future.timeout(const Duration(seconds: 10));
  } finally {
    capture.previewStatus.removeListener(listener);
  }
}

class _GatedSource extends FakeSource {
  final snapshot = Completer<FrameBuffer?>();
  @override
  Future<FrameBuffer?> latestFullResolutionFrame() => snapshot.future;
}

class _CountingSource extends FakeSource {
  int stopCalls = 0;
  @override
  Future<void> stop() async {
    stopCalls++;
    await super.stop();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'live detection and enum callbacks work with auto capture disabled',
    () async {
      final source = FakeSource();
      final capture = WindowsDocCapture.testing(frameSource: source);
      final events = <DocumentPreviewState>[];
      await capture.start(
        enableAutoCapture: false,
        onDocumentStateChanged: events.add,
      );
      expect(events, [DocumentPreviewState.processing]);
      final clear = await analyzeFrame(capture, source, fixture(sequence: 1));
      expect(clear.state, DocumentPreviewState.clear);
      expect(clear.normalizedQuad!.first.dx, closeTo(.18, .02));
      expect(clear.normalizedQuad!.first.dy, closeTo(.18, .02));
      final next = await analyzeFrame(
        capture,
        source,
        fixture(
          sequence: 2,
          quad: const [
            Offset(80, 40),
            Offset(280, 40),
            Offset(280, 190),
            Offset(80, 190),
          ],
        ),
      );
      expect(next.state, DocumentPreviewState.clear);
      expect(next.normalizedQuad!.first.dx, closeTo(.25, .02));
      expect(
        events.where((s) => s == DocumentPreviewState.clear),
        hasLength(1),
      );
      expect(events, isNot(contains(DocumentPreviewState.capturing)));
      await capture.stop();
      expect(events.last, DocumentPreviewState.idle);
      expect(capture.currentPreviewStatus.normalizedQuad, isNull);
      await capture.dispose();
      await source.stream.close();
    },
  );

  test(
    'real synthetic analysis reports missing, blurry, outside, lighting and tilt enums',
    () async {
      final source = FakeSource();
      final controller = WindowsDocCapture.testing(frameSource: source);
      await controller.start(enableAutoCapture: false);
      final cases = <(FrameBuffer, DocumentPreviewState)>[
        (
          fixture(document: false, sequence: 1),
          DocumentPreviewState.noDocument,
        ),
        (fixture(texture: false, sequence: 2), DocumentPreviewState.blurry),
        (
          fixture(
            quad: const [
              Offset(0, 30),
              Offset(210, 30),
              Offset(210, 180),
              Offset(0, 180),
            ],
            sequence: 3,
          ),
          DocumentPreviewState.outOfFrame,
        ),
        (
          fixture(paper: 40, background: 0, texture: false, sequence: 4),
          DocumentPreviewState.tooDark,
        ),
        (
          fixture(paper: 255, texture: false, sequence: 5),
          DocumentPreviewState.tooBright,
        ),
        (
          fixture(
            quad: const [
              Offset(90, 40),
              Offset(260, 40),
              Offset(285, 200),
              Offset(10, 200),
            ],
            sequence: 6,
          ),
          DocumentPreviewState.tilted,
        ),
      ];
      for (final item in cases) {
        // Re-stamp fixtures prepared before earlier analysis completed.
        final frame = item.$1;
        final value = await analyzeFrame(
          controller,
          source,
          FrameBuffer(
            width: frame.width,
            height: frame.height,
            rgba: frame.rgba,
            capturedAt: DateTime.now(),
            sequence: frame.sequence,
          ),
        );
        expect(value.state, item.$2, reason: 'sequence ${frame.sequence}');
        if (item.$2 == DocumentPreviewState.noDocument) {
          expect(value.normalizedQuad, isNull);
        }
      }
      await controller.dispose();
      await source.stream.close();
    },
  );

  test(
    'expired detection clears corners and returns processing without another camera frame',
    () async {
      final source = FakeSource();
      final capture = WindowsDocCapture.testing(frameSource: source);
      final events = <DocumentPreviewState>[];
      await capture.start(
        enableAutoCapture: false,
        onDocumentStateChanged: events.add,
      );
      await analyzeFrame(capture, source, fixture());
      expect(capture.currentPreviewStatus.normalizedQuad, hasLength(4));
      await waitForPreviewState(capture, DocumentPreviewState.processing);
      expect(capture.currentPreviewStatus.normalizedQuad, isNull);
      expect(capture.currentPreviewStatus.report, isNull);
      expect(events, [
        DocumentPreviewState.processing,
        DocumentPreviewState.clear,
        DocumentPreviewState.processing,
      ]);
      await capture.dispose();
      await source.stream.close();
    },
  );

  test(
    'manual capture publishes capturing and cooldown without needing more analysis frames',
    () async {
      final source = _GatedSource();
      final capture = WindowsDocCapture.testing(frameSource: source);
      final events = <DocumentPreviewState>[];
      await capture.start(
        enableAutoCapture: false,
        onDocumentStateChanged: events.add,
      );
      final pending = capture.captureNow();
      expect(
        capture.currentPreviewStatus.state,
        DocumentPreviewState.capturing,
      );
      source.snapshot.complete(fixture());
      expect(await pending, isNotNull);
      expect(capture.currentPreviewStatus.state, DocumentPreviewState.cooldown);
      await capture.stop();
      expect(events, [
        DocumentPreviewState.processing,
        DocumentPreviewState.capturing,
        DocumentPreviewState.cooldown,
        DocumentPreviewState.idle,
      ]);
      await capture.dispose();
      await source.stream.close();
    },
  );

  test(
    'start errors, stream errors and restart do not retain stale corners or callbacks',
    () async {
      final source = FakeSource()..fail = true;
      final capture = WindowsDocCapture.testing(frameSource: source);
      final first = <DocumentPreviewState>[];
      await expectLater(
        capture.start(onDocumentStateChanged: first.add),
        throwsStateError,
      );
      expect(first, [
        DocumentPreviewState.processing,
        DocumentPreviewState.error,
      ]);
      source.fail = false;
      final second = <DocumentPreviewState>[];
      await capture.start(
        enableAutoCapture: false,
        onDocumentStateChanged: second.add,
      );
      await analyzeFrame(capture, source, fixture());
      final stopped = waitForPreviewState(capture, DocumentPreviewState.error);
      source.stream.addError(StateError('Disconnected'));
      await stopped;
      expect(capture.currentPreviewStatus.normalizedQuad, isNull);
      await capture.stop();
      expect(capture.isRunning, isFalse);
      expect(first, [
        DocumentPreviewState.processing,
        DocumentPreviewState.error,
      ]);
      await capture.dispose();
      await source.stream.close();
    },
  );

  test(
    'throwing enum callback is surfaced on errors and does not interrupt camera operation',
    () async {
      final source = FakeSource();
      final capture = WindowsDocCapture.testing(frameSource: source);
      final error = capture.errors.first;
      await capture.start(
        enableAutoCapture: false,
        onDocumentStateChanged: (_) => throw StateError('Consumer callback'),
      );
      expect(await error, isA<StateError>());
      expect(capture.isRunning, isTrue);
      expect(
        (await analyzeFrame(capture, source, fixture())).state,
        DocumentPreviewState.clear,
      );
      await capture.dispose();
      await source.stream.close();
    },
  );

  test(
    'preview snapshots retain all warnings, prioritize framing and protect corner lists',
    () {
      final points = List<Offset>.of(normalized);
      final warnings = [
        const PreviewWarning(
          type: WarningType.blur,
          message: 'Blur',
          severity: 1,
        ),
        const PreviewWarning(
          type: WarningType.outOfFrame,
          message: 'Outside',
          severity: 1,
        ),
      ];
      final value = DocumentPreviewStatus(
        state: DocumentPreviewStatus.stateForWarnings(warnings),
        normalizedQuad: points,
        warnings: warnings,
      );
      points.clear();
      warnings.clear();
      expect(value.state, DocumentPreviewState.outOfFrame);
      expect(value.normalizedQuad, hasLength(4));
      expect(value.warnings, hasLength(2));
      expect(() => value.normalizedQuad!.clear(), throwsUnsupportedError);
      expect(
        () => DocumentPreviewStatus(
          state: DocumentPreviewState.clear,
          normalizedQuad: [Offset.zero],
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'enum callback can reenter stop without closing the native source twice',
    () async {
      final source = _CountingSource();
      final capture = WindowsDocCapture.testing(frameSource: source);
      Future<void>? nested;
      await capture.start(
        onDocumentStateChanged: (state) {
          if (state == DocumentPreviewState.idle) nested = capture.stop();
        },
      );
      await capture.stop();
      await nested;
      expect(source.stopCalls, 1);
      await capture.dispose();
      await capture.stop();
      await source.stream.close();
    },
  );
  test(
    'a preview listener stopping on a frame cannot receive a stale clear enum afterward',
    () async {
      final source = _CountingSource();
      final capture = WindowsDocCapture.testing(frameSource: source);
      final states = <DocumentPreviewState>[];
      await capture.start(
        enableAutoCapture: false,
        onDocumentStateChanged: states.add,
      );
      final stopped = Completer<void>();
      void listener() {
        if (capture.currentPreviewStatus.state == DocumentPreviewState.clear) {
          unawaited(capture.stop().then((_) => stopped.complete()));
        }
      }

      capture.previewStatus.addListener(listener);
      source.stream.add(fixture());
      await stopped.future.timeout(const Duration(seconds: 10));
      expect(states, [
        DocumentPreviewState.processing,
        DocumentPreviewState.idle,
      ]);
      expect(source.stopCalls, 1);
      expect(capture.currentPreviewStatus.normalizedQuad, isNull);
      capture.previewStatus.removeListener(listener);
      await capture.dispose();
      await source.stream.close();
    },
  );
}
