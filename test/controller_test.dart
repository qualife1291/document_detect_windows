import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'fixtures.dart';

class FakeSource implements FrameSource {
  final stream = StreamController<FrameBuffer>.broadcast();
  FrameBuffer? latest;
  bool running = false, fail = false, failStop = false;
  @override
  Stream<FrameBuffer> get frames => stream.stream;
  @override
  Size get previewSize => const Size(320, 240);
  @override
  Widget buildPreview() => const SizedBox();
  @override
  Future<List<CameraDevice>> listDevices() async => [
    const CameraDevice(id: 'fake', name: 'Synthetic'),
  ];
  @override
  Future<void> start({
    String? deviceId,
    ResolutionPreset preset = ResolutionPreset.high,
  }) async {
    if (fail) throw StateError('permission');
    running = true;
  }

  @override
  Future<void> stop() async {
    running = false;
    if (failStop) throw StateError('Native stop failed');
  }

  @override
  Future<FrameBuffer?> latestFullResolutionFrame() async => latest;
}

class PreviewSource extends FakeSource implements PreviewSamplingSource {
  @override
  bool Function()? previewSamplingAllowed;
  Completer<FrameBuffer?>? snapshotGate;
  @override
  Future<FrameBuffer?> latestFullResolutionFrame() =>
      snapshotGate?.future ?? super.latestFullResolutionFrame();
}

class CleanupSource extends FakeSource {
  final entered = Completer<void>(), opened = Completer<void>();
  bool delayedStart = false, failEnumeration = false;
  @override
  Future<List<CameraDevice>> listDevices() async {
    if (failEnumeration) throw StateError('Enumeration teardown failed');
    return super.listDevices();
  }

  int stops = 0;
  @override
  Future<void> start({
    String? deviceId,
    ResolutionPreset preset = ResolutionPreset.high,
  }) async {
    if (delayedStart) {
      entered.complete();
      await opened.future;
    }
    await super.start(deviceId: deviceId, preset: preset);
  }

  @override
  Future<void> stop() async {
    stops++;
    if (failStop) throw StateError('Device still open');
    await super.stop();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed enumeration cleanup retains ownership until stop succeeds',
    () async {
      final source = CleanupSource()
        ..failEnumeration = true
        ..failStop = true;
      final owner = WindowsDocCapture.testing(frameSource: source);
      final next = WindowsDocCapture.testing(frameSource: FakeSource());
      try {
        await expectLater(owner.listDevices(), throwsStateError);
        await expectLater(next.start(), throwsStateError);
        source.failStop = false;
        await owner.stop();
        await next.start();
      } finally {
        source.failStop = false;
        await owner.dispose();
        await next.dispose();
        await source.stream.close();
      }
    },
  );

  test(
    'failed stop blocks another owner until cleanup retry succeeds',
    () async {
      final source = CleanupSource();
      final owner = WindowsDocCapture.testing(frameSource: source);
      final next = WindowsDocCapture.testing(frameSource: FakeSource());
      try {
        await owner.start();
        source.failStop = true;
        await expectLater(owner.stop(), throwsStateError);
        expect(source.running, isTrue);
        await expectLater(next.start(), throwsStateError);
        await expectLater(owner.start(), throwsStateError);
        await expectLater(owner.listDevices(), throwsStateError);
        source.failStop = false;
        await owner.stop();
        expect(source.running, isFalse);
        await next.start();
      } finally {
        source.failStop = false;
        await owner.dispose();
        await next.dispose();
        await source.stream.close();
      }
    },
  );

  test(
    'stop during startup reports failed teardown instead of a false handoff',
    () async {
      final source = CleanupSource()..delayedStart = true;
      final owner = WindowsDocCapture.testing(frameSource: source);
      try {
        final starting = expectLater(owner.start(), throwsStateError);
        await source.entered.future;
        source.failStop = true;
        final stopping = expectLater(owner.stop(), throwsStateError);
        source.opened.complete();
        await starting;
        await stopping;
        expect(source.running, isTrue);
      } finally {
        source.failStop = false;
        await owner.dispose();
        await source.stream.close();
      }
    },
  );

  test(
    'failed dispose is retryable, terminal and closes streams only once',
    () async {
      final source = CleanupSource();
      final owner = WindowsDocCapture.testing(frameSource: source);
      final next = WindowsDocCapture.testing(frameSource: FakeSource());
      try {
        await owner.start();
        source.failStop = true;
        final closed = Future.wait([
          owner.errors.drain<void>(),
          owner.statuses.drain<void>(),
          owner.warnings.drain<void>(),
        ]);
        await expectLater(owner.dispose(), throwsStateError);
        await closed;
        await expectLater(next.start(), throwsStateError);
        source.failStop = false;
        await Future.wait([owner.dispose(), owner.dispose()]);
        expect(source.running, isFalse);
        await expectLater(owner.start(), throwsStateError);
        await next.start();
      } finally {
        source.failStop = false;
        await owner.dispose();
        await next.dispose();
        await source.stream.close();
      }
    },
  );

  test(
    'bitmap sampling pauses during capture and releases its predicate on teardown',
    () async {
      final source = PreviewSource();
      final capture = WindowsDocCapture.testing(frameSource: source);
      try {
        await capture.start(enableAutoCapture: false);
        expect(source.previewSamplingAllowed!(), isTrue);
        source.snapshotGate = Completer<FrameBuffer?>();
        final pending = capture.captureNow();
        expect(source.previewSamplingAllowed!(), isFalse);
        source.snapshotGate!.complete(null);
        expect(await pending, isNull);
        expect(source.previewSamplingAllowed!(), isTrue);
        await capture.stop();
        expect(source.previewSamplingAllowed, isNull);
        await capture.start(enableAutoCapture: false);
        expect(source.previewSamplingAllowed!(), isTrue);
        await capture.dispose();
        expect(source.previewSamplingAllowed, isNull);
      } finally {
        await capture.dispose();
        await source.stream.close();
      }
    },
  );
  test(
    'manual capture is single flight, restartable, and empty frames return null',
    () async {
      final source = FakeSource(),
          capture = WindowsDocCapture.testing(frameSource: FakeSource());
      await capture.dispose();
      final controller = WindowsDocCapture.testing(frameSource: source);
      expect(await controller.captureNow(), isNull);
      await controller.start(enableAutoCapture: false);
      source.latest = fixture();
      final pending = controller.captureNow();
      expect(await controller.captureNow(), isNull);
      expect(await pending, isNotNull);
      source.latest = fixture(document: false);
      expect(await controller.captureNow(), isNull);
      await controller.stop();
      expect(source.running, isFalse);
      await controller.start();
      await controller.dispose();
      expect(source.running, isFalse);
      await expectLater(controller.start(), throwsStateError);
      await source.stream.close();
    },
  );
  test(
    'camera error fails start and can be retried without leaking analyzer',
    () async {
      final source = FakeSource()..fail = true;
      final c = WindowsDocCapture.testing(frameSource: source);
      await expectLater(c.start(), throwsStateError);
      expect(c.isRunning, isFalse);
      source.fail = false;
      await c.start();
      expect(c.isRunning, isTrue);
      await c.dispose();
      await source.stream.close();
    },
  );
  test(
    'automatic callback uses fresh snapshot and stops on stream errors',
    () async {
      final source = FakeSource();
      final done = Completer<CapturedDocument>();
      final c = WindowsDocCapture.testing(frameSource: source);
      await c.start(onAutoCapture: done.complete);
      var index = 0;
      final timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
        source.latest = fixture(sequence: ++index);
        source.stream.add(source.latest!);
      });
      try {
        final result = await done.future.timeout(const Duration(seconds: 15));
        expect(result.croppedJpeg, isNotEmpty);
        expect(result.savedPath, isNull);
      } finally {
        timer.cancel();
      }
      final error = c.errors.first;
      source.stream.addError(StateError('unplugged'));
      await error;
      await c.stop();
      expect(c.isRunning, isFalse);
      await c.dispose();
      await source.stream.close();
    },
  );
  test(
    'production guard rejects unsupported OS or architecture before opening hardware',
    () async {
      final source = FakeSource();
      final c = WindowsDocCapture(frameSource: source);
      // The physical Windows matrix checks the opposite platform path.
      if (!Platform.isWindows) {
        await expectLater(c.start(), throwsUnsupportedError);
        expect(source.running, isFalse);
      } else {
        const channel = MethodChannel('windows_doc_capture/platform');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (_) async => 'arm64');
        await expectLater(c.start(), throwsUnsupportedError);
        expect(source.running, isFalse);
        messenger.setMockMethodCallHandler(channel, (_) async => 'x64');
        await c.start();
        expect(source.running, isTrue);
        await c.stop();
        messenger.setMockMethodCallHandler(channel, null);
      }
      await c.dispose();
      await source.stream.close();
    },
  );
  test(
    'dispose closes public streams even when native stop reports an error',
    () async {
      final source = FakeSource();
      final capture = WindowsDocCapture.testing(frameSource: source);
      await capture.start();
      final closed = Future.wait([
        capture.warnings.drain<void>(),
        capture.statuses.drain<void>(),
        capture.errors.drain<void>(),
      ]);
      source.failStop = true;
      await expectLater(capture.dispose(), throwsStateError);
      await closed.timeout(const Duration(seconds: 2));
      expect(source.running, isFalse);
      source.failStop = false;
      await capture.dispose();
      await source.stream.close();
    },
  );
}
