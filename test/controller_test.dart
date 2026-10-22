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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
      await source.stream.close();
    },
  );
}
