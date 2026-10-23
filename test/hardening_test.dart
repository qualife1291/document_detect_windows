import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'package:windows_doc_capture/src/capture/capture_cancellation.dart';
import 'controller_test.dart' show FakeSource;
import 'fixtures.dart';
import 'document_conditions_test.dart' show documentScene;

class PendingSource extends FakeSource implements AnalysisDemandSource {
  final opened = Completer<void>();
  final snapshot = Completer<FrameBuffer?>();
  bool delayStart = false;
  int starts = 0, stops = 0;
  @override
  bool Function()? analysisWanted;
  @override
  Future<void> start({
    String? deviceId,
    ResolutionPreset preset = ResolutionPreset.high,
  }) async {
    starts++;
    if (delayStart) await opened.future;
    await super.start(deviceId: deviceId, preset: preset);
  }

  @override
  Future<FrameBuffer?> latestFullResolutionFrame() => snapshot.future;
  @override
  Future<void> stop() async {
    stops++;
    await super.stop();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native operations serialize and recover after an operation fails',
    () async {
      final queue = CameraOperationQueue(), gate = Completer<void>();
      final order = <int>[];
      final first = queue.run(() async {
        order.add(1);
        await gate.future;
        throw StateError('native');
      });
      final checked = expectLater(first, throwsStateError);
      final second = queue.run(() async {
        order.add(2);
        return 42;
      });
      await Future<void>.delayed(Duration.zero);
      expect(order, [1]);
      gate.complete();
      await checked;
      expect(await second, 42);
      expect(order, [1, 2]);
    },
  );
  test(
    'another controller cannot enumerate or open an owned camera, nor stop it by disposing',
    () async {
      final source = PendingSource();
      final first = WindowsDocCapture.testing(frameSource: source);
      final second = WindowsDocCapture.testing(frameSource: source);
      await first.start();
      await expectLater(first.listDevices(), throwsStateError);
      await expectLater(second.start(), throwsStateError);
      await expectLater(second.listDevices(), throwsStateError);
      await second.dispose();
      expect(source.running, isTrue);
      expect(source.stops, 0);
      expect(source.analysisWanted, isNotNull);
      await first.dispose();
      expect(source.analysisWanted, isNull);
      final next = WindowsDocCapture.testing(frameSource: source);
      await next.start();
      await next.dispose();
      await source.stream.close();
    },
  );
  test(
    'stop during native start waits for safe native teardown and permits restart',
    () async {
      final source = PendingSource()..delayStart = true;
      final c = WindowsDocCapture.testing(frameSource: source);
      final starting = c.start();
      while (source.starts == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final checkedStart = expectLater(starting, throwsStateError);
      final stopping = c.stop();
      source.opened.complete();
      await checkedStart;
      await stopping;
      expect(source.running, isFalse);
      expect(source.stops, 1);
      await c.start();
      await c.dispose();
      await source.stream.close();
    },
  );
  test('immediate dispose cancels startup before opening hardware', () async {
    final source = PendingSource();
    final c = WindowsDocCapture.testing(frameSource: source);
    final starting = expectLater(c.start(), throwsStateError);
    await c.dispose();
    await starting;
    expect(source.starts, 0);
    expect(source.running, isFalse);
    await source.stream.close();
  });
  test(
    'stop cancels a hung snapshot and suppresses a late native result',
    () async {
      final source = PendingSource();
      final c = WindowsDocCapture.testing(frameSource: source);
      await c.start();
      final capture = c.captureNow();
      await c.stop().timeout(const Duration(seconds: 2));
      expect(await capture, isNull);
      expect(source.running, isFalse);
      source.snapshot.complete(fixture());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(c.currentPreviewStatus.state, DocumentPreviewState.idle);
      await c.dispose();
      await source.stream.close();
    },
  );
  test('concurrent dispose callers await the same teardown', () async {
    final source = PendingSource();
    final c = WindowsDocCapture.testing(frameSource: source);
    await c.start();
    final first = c.dispose(), second = c.dispose();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
    expect(source.stops, 1);
    await source.stream.close();
  });
  test(
    'capture cancellation terminates CPU worker without waiting for computation',
    () async {
      final ready = ReceivePort(), cancellation = CaptureCancellation();
      final port = ready.sendPort;
      final work = runCaptureWorker<int>(() {
        port.send('ready');
        while (true) {}
      }, cancellation: cancellation);
      await ready.first.timeout(const Duration(seconds: 5));
      ready.close();
      cancellation.cancel();
      expect(await work.timeout(const Duration(seconds: 2)), isNull);
    },
  );
  test(
    'worker timeout and errors propagate without leaving a live worker',
    () async {
      await expectLater(
        runCaptureWorker<int>(() => throw StateError('test failure')),
        throwsA(isA<RemoteError>()),
      );
      await expectLater(
        runCaptureWorker<int>(() async {
          await Future<void>.delayed(const Duration(days: 1));
          return 1;
        }, timeout: const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );
    },
  );
  test('pre-cancelled crop cannot create files or begin processing', () async {
    final cancellation = CaptureCancellation()..cancel();
    expect(
      await const CropPipeline().capture(
        fixture(),
        saveDirectory: 'not-created',
        cancellation: cancellation,
      ),
      isNull,
    );
  });
  test(
    'closing during an 8MP crop cancels worker and leaves no output file',
    () async {
      final directory = await Directory.systemTemp.createTemp('cancel-8mp-');
      final source = FakeSource();
      final c = WindowsDocCapture.testing(frameSource: source);
      try {
        await c.start(saveDirectory: directory.path);
        source.latest = documentScene(width: 3264, height: 2448);
        final result = c.captureNow();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await c.dispose().timeout(const Duration(seconds: 3));
        expect(await result, isNull);
        expect(await directory.list().toList(), isEmpty);
        expect(source.running, isFalse);
      } finally {
        await c.dispose();
        await source.stream.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test('late native snapshot errors are consumed after cancellation', () async {
    final source = PendingSource();
    final c = WindowsDocCapture.testing(frameSource: source);
    await c.start();
    final result = c.captureNow();
    await c.dispose();
    expect(await result, isNull);
    source.snapshot.completeError(StateError('late unplug'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await source.stream.close();
  });
  test(
    'analyzer disposed during startup cannot accept frames or restart',
    () async {
      final analyzer = DocumentQualityAnalyzer();
      final starting = analyzer.start();
      final first = analyzer.dispose(), second = analyzer.dispose();
      expect(identical(first, second), isTrue);
      await starting;
      await first;
      analyzer.add(fixture());
      expect(analyzer.pendingFrames, 0);
      expect(analyzer.canAcceptFrame, isFalse);
      await expectLater(analyzer.start(), throwsStateError);
    },
  );
  test(
    'analysis expiry preserves removal requirement after capture across days',
    () {
      final auto = AutoCaptureController()..captureCompleted(Duration.zero);
      for (var day = 1; day <= 7; day++) {
        auto.invalidateFrames();
        expect(auto.update(good(), normalized, Duration(days: day)), isFalse);
        expect(auto.state, AutoCaptureState.cooldown);
      }
      auto.update(DetectionResult.empty(), null, const Duration(days: 8));
      auto.update(
        good(),
        normalized,
        const Duration(days: 8, milliseconds: 100),
      );
      expect(auto.state, AutoCaptureState.stable);
    },
  );
  test(
    'repeated sessions release workers, frame subscriptions and camera ownership',
    () async {
      final source = FakeSource();
      for (var i = 0; i < 50; i++) {
        final c = WindowsDocCapture.testing(frameSource: source);
        await c.start(enableAutoCapture: false);
        expect(source.stream.hasListener, isTrue);
        await c.dispose();
        expect(source.stream.hasListener, isFalse);
        expect(source.running, isFalse);
      }
      await source.stream.close();
    },
  );
}
