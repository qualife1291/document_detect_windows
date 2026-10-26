import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'package:windows_doc_capture_example/capture_app.dart';
import 'package:windows_doc_capture_example/capture_result_image.dart';
import 'package:windows_doc_capture_example/capture_pair_exporter.dart';
import '../../test/fixtures.dart';

class _Source implements FrameSource {
  Completer<void>? stopGate, startGate;
  Completer<FrameBuffer?>? snapshotGate;
  int stops = 0;
  final presets = <ResolutionPreset>[];
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
  }) async {
    presets.add(preset);
    await startGate?.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    await stopGate?.future;
  }

  @override
  Future<FrameBuffer?> latestFullResolutionFrame() async =>
      snapshotGate == null ? fixture() : await snapshotGate!.future;
}

class _PairExporter extends CapturePairExporter {
  var picker = Completer<String?>();
  var write = Completer<Directory?>();
  int picks = 0, writes = 0;
  CapturedDocument? received;
  bool Function()? cancelled;
  @override
  Future<String?> chooseDirectory({String? initialDirectory}) {
    picks++;
    return picker.future;
  }

  @override
  Future<Directory?> writePair(
    CapturedDocument document,
    Directory parent, {
    required bool Function() isCancelled,
  }) {
    writes++;
    received = document;
    cancelled = isCancelled;
    return write.future;
  }
}

Future<(WindowsDocCapture, _Source)> _pairResult(
  WidgetTester tester,
  CapturePairExporter exporter, {
  bool logging = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 960));
  final source = _Source();
  final capture = WindowsDocCapture.testing(
    frameSource: source,
    enableDebugLogging: logging,
  );
  await tester.pumpWidget(CaptureApp(capture: capture, pairExporter: exporter));
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(find.text('Bắt đầu'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(find.text('Chụp ngay'));
    await Future<void>.delayed(const Duration(seconds: 1));
  });
  await tester.pumpAndSettle();
  expect(find.text('Đã chụp giấy tờ'), findsOneWidget);
  expect(capture.isRunning, isFalse);
  return (capture, source);
}

Future<void> _closePairResult(
  WidgetTester tester,
  (WindowsDocCapture, _Source) owned,
) async {
  await tester.runAsync(() async {
    await owned.$1.stop();
  });

  await tester.pumpWidget(const SizedBox.shrink());

  await tester.runAsync(() async {
    await owned.$1.dispose();

    await owned.$2.controller.close();
  });
  await tester.binding.setSurfaceSize(null);
}

void _hideKiosk(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
}

void _resumeKiosk(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void main() {
  testWidgets(
    'pair picker cancellation blocks duplicate exports and Esc without restarting camera',
    (tester) async {
      final exporter = _PairExporter();
      final owned = await _pairResult(tester, exporter);
      try {
        final button = find
            .ancestor(
              of: find.text('Xuất cặp ảnh gốc + crop'),
              matching: find.byWidgetPredicate(
                (widget) => widget is FilledButton,
              ),
            )
            .first;
        final originalCallback = tester.widget<FilledButton>(button).onPressed!;
        await tester.tap(button);
        originalCallback(); // stale callback / double click is guarded
        await tester.pumpAndSettle();
        expect(exporter.picks, 1);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Chụp lại (Esc)'),
              )
              .onPressed,
          isNull,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(owned.$2.presets, hasLength(1));
        exporter.picker.complete(null);
        await tester.pumpAndSettle();
        expect(exporter.writes, 0);
        expect(find.text('Đã hủy xuất cặp ảnh.'), findsOneWidget);
        expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
        expect(owned.$1.isRunning, isFalse);
      } finally {
        await _closePairResult(tester, owned);
      }
    },
  );

  testWidgets(
    'pair export waits for both files and leaves the same captured result visible',
    (tester) async {
      final exporter = _PairExporter();
      final owned = await _pairResult(tester, exporter);
      try {
        final shown = tester
            .widget<CaptureResultImage>(find.byType(CaptureResultImage))
            .bytes;
        await tester.tap(find.text('Xuất cặp ảnh gốc + crop'));
        exporter.picker.complete('/selected-output');
        await tester.pumpAndSettle();
        expect(exporter.writes, 1);
        expect(exporter.received!.croppedJpeg, same(shown));
        expect(find.text('Đã xuất đủ ảnh gốc và ảnh crop.'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(owned.$2.presets, hasLength(1));
        exporter.write.complete(Directory('/selected-output/capture-pair'));
        await tester.pumpAndSettle();
        expect(find.text('Đã xuất đủ ảnh gốc và ảnh crop.'), findsOneWidget);
        expect(find.text('/selected-output/capture-pair'), findsOneWidget);
        expect(owned.$1.isRunning, isFalse);
        expect(
          tester
              .widget<CaptureResultImage>(find.byType(CaptureResultImage))
              .bytes,
          same(shown),
        );
      } finally {
        await _closePairResult(tester, owned);
      }
    },
  );

  testWidgets(
    'pair IO error stays readable without private exception text and permits retry',
    (tester) async {
      final messages = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) messages.add(message);
      };
      final exporter = _PairExporter();
      final owned = await _pairResult(tester, exporter, logging: true);
      try {
        await tester.tap(find.text('Xuất cặp ảnh gốc + crop'));
        exporter.picker.complete('/selected-output');
        await tester.pumpAndSettle();
        exporter.write.completeError(
          const FileSystemException('/private/document-data'),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Không xuất được cặp ảnh.'), findsOneWidget);
        expect(find.textContaining('/private/document-data'), findsNothing);
        expect(find.text('Đã chụp giấy tờ'), findsOneWidget);
        exporter.picker = Completer<String?>();
        exporter.write = Completer<Directory?>();
        await tester.tap(find.text('Xuất cặp ảnh gốc + crop'));
        exporter.picker.complete('/other-output');
        await tester.pumpAndSettle();
        exporter.write.complete(Directory('/other-output/pair'));
        await tester.pumpAndSettle();
        expect(exporter.writes, 2);
        final events = messages
            .where((m) => m.contains('"event":"export_pair"'))
            .map(
              (m) =>
                  jsonDecode(m.substring(m.indexOf('{')))
                      as Map<String, dynamic>,
            )
            .toList();
        expect(events.map((e) => e['outcome']), [
          'start',
          'error',
          'start',
          'success',
        ]);
        expect(messages.join(), isNot(contains('/private/document-data')));
        expect(messages.join(), isNot(contains('/selected-output')));
        expect(messages.join(), isNot(contains('/other-output')));
        expect(find.text('Đã xuất đủ ảnh gốc và ảnh crop.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await _closePairResult(tester, owned);
        debugPrint = previousDebugPrint;
      }
    },
  );

  testWidgets(
    'closing while folder picker is open never starts a late export',
    (tester) async {
      final exporter = _PairExporter();
      final owned = await _pairResult(tester, exporter);
      await tester.tap(find.text('Xuất cặp ảnh gốc + crop'));
      await tester.pumpAndSettle();
      await _closePairResult(tester, owned);
      exporter.picker.complete('/late-output');
      await tester.pumpAndSettle();
      expect(exporter.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unmount cancels pending pair write without updating disposed widgets',
    (tester) async {
      final exporter = _PairExporter();
      final owned = await _pairResult(tester, exporter);
      await tester.tap(find.text('Xuất cặp ảnh gốc + crop'));
      exporter.picker.complete('/selected-output');
      await tester.pumpAndSettle();
      expect(exporter.cancelled!(), isFalse);
      await _closePairResult(tester, owned);
      expect(exporter.cancelled!(), isTrue);
      exporter.write.complete(null);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'graceful exit awaits cancellation of an in-progress pair write',
    (tester) async {
      final exporter = _PairExporter();
      final owned = await _pairResult(tester, exporter);
      try {
        await tester.tap(find.text('Xuất cặp ảnh gốc + crop'));
        exporter.picker.complete('/selected-output');
        await tester.pumpAndSettle();
        var exited = false;
        final exit = tester.binding.handleRequestAppExit().then((value) {
          exited = true;
          return value;
        });
        await tester.pump();
        expect(exporter.cancelled!(), isTrue);
        expect(exited, isFalse);
        exporter.write.complete(null);
        await tester.pumpAndSettle();
        expect(await exit, AppExitResponse.exit);
      } finally {
        await _closePairResult(tester, owned);
      }
    },
  );

  testWidgets(
    'hidden kiosk stops fully, waits for cleanup and requires explicit restart',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      _resumeKiosk(tester);
      final source = _Source();
      final capture = WindowsDocCapture.testing(frameSource: source);
      await tester.pumpWidget(CaptureApp(capture: capture));
      await tester.pumpAndSettle();
      try {
        expect(find.byType(Checkbox), findsNothing);
        expect(find.byType(TextField), findsNothing);
        await tester.runAsync(() async {
          await tester.tap(find.text('Bắt đầu'));
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();
        // Inactive includes focus loss/native dialogs; do not close the device.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();

        expect(capture.isRunning, isTrue);

        expect(source.stops, 0);
        source.stopGate = Completer<void>();
        await tester.runAsync(() async {
          _hideKiosk(tester);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();

        expect(capture.isRunning, isFalse);
        _resumeKiosk(tester);
        await tester.pump();
        expect(find.byType(DocumentCameraPreview), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Bắt đầu'),
              )
              .onPressed,
          isNull,
        );
        await tester.runAsync(() async {
          source.stopGate!.complete();
          source.stopGate = null;
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await tester.pumpAndSettle();

        expect(source.presets, hasLength(1));

        expect(capture.isRunning, isFalse);
        await tester.runAsync(() async {
          await tester.tap(find.text('Bắt đầu'));
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();

        expect(capture.isRunning, isTrue);

        expect(source.presets, hasLength(2));
      } finally {
        _resumeKiosk(tester);
        await tester.runAsync(() async {
          if (source.stopGate != null && !source.stopGate!.isCompleted) {
            source.stopGate!.complete();
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await _closePairResult(tester, (capture, source));
      }
    },
  );

  testWidgets(
    'hide during native startup rejects late start without a false camera error',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      _resumeKiosk(tester);
      final source = _Source();
      final capture = WindowsDocCapture.testing(frameSource: source);
      await tester.pumpWidget(CaptureApp(capture: capture));
      await tester.pumpAndSettle();
      try {
        await tester.runAsync(() async {
          source.startGate = Completer<void>();
          await tester.tap(find.text('Bắt đầu'));
          final deadline = DateTime.now().add(const Duration(seconds: 3));
          while (source.presets.isEmpty && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(source.presets, hasLength(1));
          _hideKiosk(tester);
          source.startGate!.complete();
          final stopDeadline = DateTime.now().add(const Duration(seconds: 3));
          while (source.stops == 0 && DateTime.now().isBefore(stopDeadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        _resumeKiosk(tester);
        await tester.pumpAndSettle();
        expect(capture.isRunning, isFalse);
        expect(source.stops, 1);
        expect(find.textContaining('Không mở được camera'), findsNothing);
        expect(find.byType(DocumentCameraPreview), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Bắt đầu'),
              )
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (!source.startGate!.isCompleted) source.startGate!.complete();
        await _closePairResult(tester, (capture, source));
        _resumeKiosk(tester);
      }
    },
  );

  testWidgets(
    'hide during snapshot cancels capture and rejects the late JPEG',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      _resumeKiosk(tester);
      final source = _Source()..snapshotGate = Completer<FrameBuffer?>();
      final capture = WindowsDocCapture.testing(frameSource: source);
      await tester.pumpWidget(CaptureApp(capture: capture));
      await tester.pumpAndSettle();
      try {
        await tester.runAsync(() async {
          await tester.tap(find.text('Bắt đầu'));
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('Chụp ngay'));
          _hideKiosk(tester);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          source.snapshotGate!.complete(fixture());
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        _resumeKiosk(tester);
        await tester.pumpAndSettle();
        expect(capture.isRunning, isFalse);
        expect(find.byType(CaptureResultImage), findsNothing);
        expect(find.textContaining('Chưa thấy đủ bốn góc'), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Bắt đầu'),
              )
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _closePairResult(tester, (capture, source));
        _resumeKiosk(tester);
      }
    },
  );

  testWidgets('hide and resume permanently cancel an open export picker', (
    tester,
  ) async {
    _resumeKiosk(tester);
    final exporter = _PairExporter();
    final owned = await _pairResult(tester, exporter);
    try {
      await tester.tap(find.text('Xuất cặp ảnh gốc + crop'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        _hideKiosk(tester);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      _resumeKiosk(tester);
      await tester.pump();
      exporter.picker.complete('/late-after-resume');
      await tester.pumpAndSettle();
      expect(exporter.writes, 0);
      expect(find.text('Đã chụp giấy tờ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      _resumeKiosk(tester);
      await _closePairResult(tester, owned);
    }
  });

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
      expect(
        tester
            .widget<DropdownButton<ResolutionPreset>>(
              find.byType(DropdownButton<ResolutionPreset>),
            )
            .value,
        ResolutionPreset.high,
      );
      await tester.tap(find.byType(DropdownButton<ResolutionPreset>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chi tiết cao').last);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Bắt đầu'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Camera đang hoạt động'), findsOneWidget);
      expect(source.presets, [ResolutionPreset.veryHigh]);
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
      expect(
        tester
            .widget<DropdownButton<ResolutionPreset>>(
              find.byType(DropdownButton<ResolutionPreset>),
            )
            .onChanged,
        isNotNull,
      );
      expect(find.byType(DocumentCameraPreview), findsNothing);
      await tester.runAsync(() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      await tester.pumpAndSettle();
      expect(find.text('Đã chụp giấy tờ'), findsNothing);
      expect(source.presets, [
        ResolutionPreset.veryHigh,
        ResolutionPreset.veryHigh,
      ]);
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
    'result never enlarges decoded pixels at 100/150/200 percent DPI',
    (tester) async {
      final result = (await tester.runAsync(
        () => const CropPipeline().capture(fixture(width: 640, height: 480)),
      ))!;
      Object? previousKey;
      for (final ratio in [1.0, 1.5, 2.0]) {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(devicePixelRatio: ratio),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: SizedBox(
                  width: 400,
                  height: 300,
                  child: CaptureResultImage(
                    bytes: result.originalJpeg,
                    maxDimension: 128,
                  ),
                ),
              ),
            ),
          ),
        );
        for (
          var i = 0;
          i < 100 &&
              tester.renderObject<RenderImage>(find.byType(RawImage)).image ==
                  null;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        final render = tester.renderObject<RenderImage>(find.byType(RawImage));
        expect(render.image, isNotNull);
        expect(render.image!.width, 128);
        expect(render.image!.height, 96);
        expect(render.scale, ratio);
        final destination = applyBoxFit(
          render.fit!,
          Size(
            render.image!.width / render.scale,
            render.image!.height / render.scale,
          ),
          render.size,
        ).destination;
        expect(destination.width * ratio, closeTo(128, .001));
        expect(destination.height * ratio, closeTo(96, .001));
        final provider = tester.widget<Image>(find.byType(Image)).image;
        final key = await provider.obtainKey(ImageConfiguration.empty);
        if (previousKey != null) {
          expect(
            PaintingBinding.instance.imageCache.containsKey(previousKey),
            isFalse,
          );
        }
        previousKey = key;
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        PaintingBinding.instance.imageCache.containsKey(previousKey!),
        isFalse,
      );
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
