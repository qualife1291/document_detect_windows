import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'package:windows_doc_capture_example/capture_app.dart';
import '../../test/fixtures.dart';

class _Source implements FrameSource {
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
  Future<void> stop() async {}
  @override
  Future<FrameBuffer?> latestFullResolutionFrame() async => fixture();
}

void main() {
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
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Đã chụp giấy tờ'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await capture.dispose();
        await source.controller.close();
      });
      await tester.binding.setSurfaceSize(null);
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
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await capture.dispose();
        await source.controller.close();
      });
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.binding.setSurfaceSize(null);
    },
  );
}
