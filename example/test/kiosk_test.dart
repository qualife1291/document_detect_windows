import 'dart:async';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'package:windows_doc_capture_example/capture_app.dart';
import 'package:windows_doc_capture_example/capture_result_image.dart';
import '../../test/fixtures.dart';

class _Source implements FrameSource {
  Completer<void>? stopGate;
  final controller = StreamController<FrameBuffer>.broadcast();
  @override
  Stream<FrameBuffer> get frames => controller.stream;
  @override
  Size get previewSize => const Size(320, 240);
  @override
  Widget buildPreview() => const ColoredBox(color: Colors.black);
  @override
  Future<List<CameraDevice>> listDevices() async => [
    const CameraDevice(id: 'synthetic', name: 'Camera kiểm thử'),
  ];
  @override
  Future<void> start({
    String? deviceId,
    ResolutionPreset preset = ResolutionPreset.high,
  }) async {}
  @override
  Future<void> stop() async {
    await stopGate?.future;
  }

  @override
  Future<FrameBuffer?> latestFullResolutionFrame() async => fixture();
}

void main() {
  testWidgets('graceful window exit awaits camera cleanup', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 960));
    final source = _Source();
    final capture = WindowsDocCapture.testing(frameSource: source);
    await tester.pumpWidget(CaptureApp(capture: capture));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Bắt đầu'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(capture.isRunning, isTrue);
    await tester.runAsync(() async {
      source.stopGate = Completer<void>();
      var completed = false;
      final exit = tester.binding.handleRequestAppExit().then((response) {
        completed = true;
        return response;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(completed, isFalse);
      source.stopGate!.complete();
      expect(await exit, AppExitResponse.exit);
      expect(capture.isRunning, isFalse);
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await capture.dispose();
      await source.controller.close();
    });
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets(
    'Vietnamese kiosk supports start, manual result, retake and Esc',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      final source = _Source();
      final capture = WindowsDocCapture.testing(frameSource: source);
      await tester.pumpWidget(CaptureApp(capture: capture));
      await tester.pumpAndSettle();
      expect(find.text('Camera kiểm thử'), findsOneWidget);
      expect(find.text('Đưa giấy tờ vào khung'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Bắt đầu'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Camera đang hoạt động'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Chụp ngay'));
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      await tester.pumpAndSettle();
      expect(find.text('Đã chụp giấy tờ'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Ảnh giấy tờ đã cắt và chỉnh phối cảnh'),
        findsOneWidget,
      );
      expect(capture.isRunning, isFalse);
      expect(find.byType(DocumentCameraPreview), findsNothing);
      await tester.runAsync(() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      await tester.pumpAndSettle();
      expect(find.text('Đã chụp giấy tờ'), findsNothing);
      expect(tester.takeException(), isNull);
      // Await real isolate cleanup outside the fake widget clock, before
      // unmounting starts the same disposal future from State.dispose().
      await tester.runAsync(() async {
        await capture.dispose();
        await source.controller.close();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets(
    'result waits for native stop and removes live preview before JPEG display',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      final source = _Source();
      final capture = WindowsDocCapture.testing(frameSource: source);
      await tester.pumpWidget(CaptureApp(capture: capture));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Bắt đầu'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      source.stopGate = Completer<void>();
      await tester.runAsync(() async {
        await tester.tap(find.text('Chụp ngay'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pumpAndSettle();
      expect(capture.isRunning, isFalse);
      expect(find.byType(DocumentCameraPreview), findsNothing);
      expect(find.text('Đã chụp giấy tờ'), findsNothing);
      await tester.runAsync(() async {
        source.stopGate!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Đã chụp giấy tờ'), findsOneWidget);
      expect(find.byType(CaptureResultImage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await capture.dispose();
        await source.controller.close();
      });
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets(
    'six capture/retake cycles evict only result images and stop camera on results',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      final source = _Source();
      final capture = WindowsDocCapture.testing(frameSource: source);
      final cache = PaintingBinding.instance.imageCache;
      final unrelatedKey = Object();
      await tester.pumpWidget(CaptureApp(capture: capture));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Bắt đầu'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      final originalEntries = cache.currentSize;
      // An unrelated loading image belongs to the host app. Result cleanup
      // must preserve it, including its pending load/listener.
      final unrelatedLoad = Completer<ImageInfo>();
      cache.putIfAbsent(
        unrelatedKey,
        () => OneFrameImageStreamCompleter(unrelatedLoad.future),
      );
      await tester.pump();

      for (var cycle = 0; cycle < 6; cycle++) {
        await tester.runAsync(() async {
          await tester.tap(find.text('Chụp ngay'));
          final deadline = DateTime.now().add(const Duration(seconds: 3));
          while (capture.isRunning && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
        expect(find.text('Đã chụp giấy tờ'), findsOneWidget);
        expect(capture.isRunning, isFalse);
        expect(find.byType(DocumentCameraPreview), findsNothing);
        final provider =
            tester.widget<Image>(find.byType(Image)).image as ResizeImage;
        final key = await provider.obtainKey(ImageConfiguration.empty);
        await tester.runAsync(() async {
          await tester.tap(find.text('Chụp lại (Esc)'));
          await Future<void>.delayed(const Duration(milliseconds: 120));
        });
        await tester.pumpAndSettle();
        expect(capture.isRunning, isTrue);
        expect(cache.containsKey(key), isFalse);
        expect(cache.containsKey(unrelatedKey), isTrue);
        expect(cache.statusForKey(unrelatedKey).pending, isTrue);
        expect(cache.currentSize, lessThanOrEqualTo(originalEntries + 1));
        expect(tester.takeException(), isNull);
      }
      expect(cache.evict(unrelatedKey), isTrue);
      await tester.pumpAndSettle();
      expect(cache.containsKey(unrelatedKey), isFalse);
      // Complete native/isolate cleanup in the real async zone before unmount
      // starts its own unawaited fallback disposal in FakeAsync.
      await tester.runAsync(() async {
        await capture.dispose();
        await source.controller.close();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets(
    'result display decode fits a cap and evicts cached image on close',
    (tester) async {
      final result = (await tester.runAsync(
        () => const CropPipeline().capture(fixture(width: 640, height: 480)),
      ))!;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CaptureResultImage(
            bytes: result.originalJpeg,
            maxDimension: 128,
          ),
        ),
      );
      final provider = tester.widget<Image>(find.byType(Image)).image;
      final key = await provider.obtainKey(ImageConfiguration.empty);
      ImageInfo? decoded;
      final stream = provider.resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener((info, _) {
        decoded?.dispose();
        decoded = info;
      });
      stream.addListener(listener);
      try {
        for (var i = 0; i < 100 && decoded == null; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(decoded, isNotNull);
        expect(decoded!.image.width, 128);
        expect(decoded!.image.height, 96);
      } finally {
        stream.removeListener(listener);
        decoded?.dispose();
      }
      await tester.pumpAndSettle();
      expect(PaintingBinding.instance.imageCache.containsKey(key), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(PaintingBinding.instance.imageCache.containsKey(key), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'all quality warnings remain readable on a reduced-motion kiosk',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      final source = _Source();
      final capture = WindowsDocCapture.testing(frameSource: source);
      await tester.pumpWidget(CaptureApp(capture: capture));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Bắt đầu'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        source.controller.add(
          fixture(paper: 40, background: 0, texture: false),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Quá tối'), findsOneWidget);
      expect(find.textContaining('Ảnh bị mờ'), findsOneWidget);
      await tester.runAsync(() async {
        source.controller.add(fixture());
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('Chuẩn bị chụp — giữ yên'), findsOneWidget);
      expect(find.byType(DocumentCameraPreview), findsOneWidget);
      final corners = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<DocumentCornersPainter>()
          .single;
      expect(corners.normalizedQuad, hasLength(4));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      // Await real isolate cleanup outside the fake widget clock, before
      // unmounting starts the same disposal future from State.dispose().
      await tester.runAsync(() async {
        await capture.dispose();
        await source.controller.close();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.binding.setSurfaceSize(null);
    },
  );
}
