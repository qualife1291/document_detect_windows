import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'package:windows_doc_capture_uvc/windows_doc_capture_uvc.dart';
import 'package:windows_doc_capture_example/capture_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'physical camera: preview, paper, auto callback, cropped result and file',
    (tester) async {
      expect(
        Platform.isWindows,
        isTrue,
        reason: 'Physical Windows x64 runner required',
      );
      final directory = await Directory.systemTemp.createTemp(
        'document-capture-integration-',
      );
      final capture = WindowsDocCapture(frameSource: UvcFrameSource());
      try {
        await tester.pumpWidget(CaptureApp(capture: capture));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), directory.path);
        await tester.tap(find.text('Bắt đầu'));
        final watch = Stopwatch()..start();
        while (find.text('Camera đang hoạt động').evaluate().isEmpty &&
            watch.elapsed < const Duration(seconds: 30)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Camera đang hoạt động'), findsOneWidget);
        // Place a textured A4/ID document in the frame and hold it still. No
        // personal image or path is printed or uploaded as a CI artifact.
        while (find.text('Đã chụp giấy tờ').evaluate().isEmpty &&
            watch.elapsed < const Duration(minutes: 2)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Đã chụp giấy tờ'), findsOneWidget);
        final files = await directory
            .list()
            .where((f) => f is File && f.path.endsWith('.jpg'))
            .toList();
        expect(files, hasLength(1));
        final bytes = await File(files.single.path).readAsBytes();
        expect(bytes.length, greaterThan(100));
        expect(bytes.take(2), [0xff, 0xd8]);
        expect(
          find.bySemanticsLabel('Ảnh giấy tờ đã cắt và chỉnh phối cảnh'),
          findsOneWidget,
        );
        await tester.tap(find.text('Chụp lại (Esc)'));
        await tester.pumpAndSettle();
        expect(find.text('Đã chụp giấy tờ'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await capture.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
}
