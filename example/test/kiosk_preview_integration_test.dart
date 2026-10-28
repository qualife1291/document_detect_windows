import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'package:windows_doc_capture_example/integration/camera_preview_widget.dart';

import '../../test/fixtures.dart';

class _Source implements FrameSource {
  final framesController = StreamController<FrameBuffer>.broadcast();
  final events = <String>[];
  final devices = <CameraDevice>[
    const CameraDevice(id: 'test-document', name: 'Document camera'),
  ];
  Completer<void>? stopGate;
  Completer<FrameBuffer?>? snapshotGate;
  bool running = false, document = true;
  int starts = 0;
  String? selected;
  @override
  Stream<FrameBuffer> get frames => framesController.stream;
  @override
  Size get previewSize => const Size(320, 240);
  @override
  Widget buildPreview() => const ColoredBox(color: Colors.black);
  @override
  Future<List<CameraDevice>> listDevices() async => devices;
  @override
  Future<void> start({
    String? deviceId,
    ResolutionPreset preset = ResolutionPreset.high,
  }) async {
    starts++;
    selected = deviceId;
    running = true;
    events.add('start');
  }

  @override
  Future<void> stop() async {
    if (running) {
      await stopGate?.future;
      running = false;
      events.add('stop');
    }
  }

  @override
  Future<FrameBuffer?> latestFullResolutionFrame() async =>
      snapshotGate == null ? fixture(document: document) : snapshotGate!.future;
}

WindowsDocCapture _capture(_Source source) => WindowsDocCapture.testing(
  frameSource: source,
  analysisInterval: const Duration(milliseconds: 50),
  autoCapture: AutoCaptureController(stableFrameCount: 2),
);

Future<void> _mount(WidgetTester tester, CameraPreviewWidget preview) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: preview)));
  await tester.pump();
}

Future<void> _close(
  WidgetTester tester,
  CameraPreviewController controller,
  _Source source,
) async {
  await tester.runAsync(controller.shutdown);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() async {
    await controller.stop();
    await source.framesController.close();
  });
}

Future<void> _verifyJpeg(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    expect(frame.image.width, greaterThan(0));
    expect(frame.image.height, greaterThan(0));
    frame.image.dispose();
  } finally {
    codec.dispose();
  }
}

void main() {
  testWidgets(
    'manual capture stops and releases hardware before exactly one JPEG callback',
    (tester) async {
      final source = _Source(), controller = CameraPreviewController();
      var controllerCalls = 0, widgetCalls = 0;
      Uint8List? bytes;
      controller.onCaptured = (_) => controllerCalls++;
      final capture = _capture(source);
      await _mount(
        tester,
        CameraPreviewWidget(
          controller: controller,
          autoStart: false,
          captureMode: DocumentCameraCaptureMode.single,
          captureFactory: () => capture,
          acquireHardware: () async {
            source.events.add('lease');
            return () async {
              source.events.add('release');
            };
          },
          onCaptured: (jpeg) {
            expect(source.running, isFalse);
            expect(source.events.last, 'release');
            source.events.add('callback');
            widgetCalls++;
            bytes = jpeg;
          },
        ),
      );
      try {
        await tester.runAsync(controller.resume);
        await tester.pump();
        expect(find.byType(DocumentCameraPreview), findsOneWidget);
        await tester.runAsync(controller.capture);
        await tester.pump();
        expect(bytes, isNotNull);
        await tester.runAsync(() => _verifyJpeg(bytes!));
        expect(controllerCalls, 0);
        expect(widgetCalls, 1);
        expect(source.events, [
          'lease',
          'start',
          'stop',
          'release',
          'callback',
        ]);
        expect(find.byType(DocumentCameraPreview), findsNothing);
      } finally {
        await _close(tester, controller, source);
      }
    },
  );

  testWidgets(
    'auto capture uses the existing bytes callback after stop and survives parent rebuilds',
    (tester) async {
      final source = _Source(), controller = CameraPreviewController();
      final captured = Completer<Uint8List>();
      controller.onCaptured = captured.complete;
      final capture = _capture(source);
      final states = <DocumentPreviewState>[];
      CameraPreviewWidget preview() => CameraPreviewWidget(
        controller: controller,
        autoStart: false,
        enableAutoCapture: true,
        captureMode: DocumentCameraCaptureMode.single,
        captureFactory: () => capture,
        onDocumentStateChanged: states.add,
      );
      await _mount(tester, preview());
      try {
        await tester.runAsync(controller.resume);
        for (var i = 0; i < 15 && !captured.isCompleted; i++) {
          await tester.pumpWidget(MaterialApp(home: Scaffold(body: preview())));
          await tester.runAsync(() async {
            source.framesController.add(fixture(sequence: i + 1));
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await tester.pump();
        }
        expect(captured.isCompleted, isTrue);
        expect(source.running, isFalse);
        expect(source.starts, 1);
        expect(states, contains(DocumentPreviewState.clear));
        await tester.runAsync(() async => _verifyJpeg(await captured.future));
      } finally {
        await _close(tester, controller, source);
      }
    },
  );

  testWidgets(
    'stop cancels pending snapshot, suppresses late callbacks, and permits explicit resume',
    (tester) async {
      final source = _Source(), controller = CameraPreviewController();
      var calls = 0;
      controller.onCaptured = (_) => calls++;
      await _mount(
        tester,
        CameraPreviewWidget(
          controller: controller,
          autoStart: false,
          captureFactory: () => _capture(source),
        ),
      );
      try {
        await tester.runAsync(() async {
          await controller.resume();

          source.snapshotGate = Completer<FrameBuffer?>();
          final taking = controller.capture();
          await controller.stop();

          await taking;

          source.snapshotGate!.complete(fixture());
          source.snapshotGate = null;
          await controller.resume();
        });
        await tester.pump();
        expect(calls, 0);
        expect(source.starts, 2);
        expect(source.running, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, controller, source);
      }
    },
  );

  testWidgets(
    'a stale hardware acquisition releases its lease before stop completes',
    (tester) async {
      final source = _Source(), controller = CameraPreviewController();
      late Completer<CameraHardwareRelease> acquired;
      var released = false;
      await _mount(
        tester,
        CameraPreviewWidget(
          controller: controller,
          autoStart: false,
          captureFactory: () => _capture(source),
          acquireHardware: () => acquired.future,
        ),
      );
      try {
        await tester.runAsync(() async {
          acquired = Completer<CameraHardwareRelease>();
          final starting = controller.resume();
          await Future<void>.delayed(Duration.zero);
          var stopped = false;
          final stopping = controller.stop().then((_) => stopped = true);
          await Future<void>.delayed(Duration.zero);
          expect(stopped, isFalse);
          acquired.complete(() async {
            released = true;
          });
          await starting;
          await stopping;
        });
        expect(released, isTrue);
        expect(source.starts, 0);
      } finally {
        await _close(tester, controller, source);
      }
    },
  );

  testWidgets(
    'multiple devices require explicit selection and never fall back',
    (tester) async {
      final source = _Source(), controller = CameraPreviewController();
      source.devices.add(
        const CameraDevice(id: 'test-face', name: 'Face camera'),
      );
      await _mount(
        tester,
        CameraPreviewWidget(
          controller: controller,
          autoStart: false,
          captureFactory: () => _capture(source),
        ),
      );
      try {
        await tester.runAsync(
          () => expectLater(controller.resume(), throwsStateError),
        );
        await tester.pump();
        expect(source.starts, 0);
        expect(
          find.textContaining('Không mở được camera giấy tờ'),
          findsOneWidget,
        );
      } finally {
        await _close(tester, controller, source);
      }
    },
  );

  testWidgets(
    'hidden stops camera and lease; foreground does not reopen automatically',
    (tester) async {
      final source = _Source(), controller = CameraPreviewController();
      var released = false;
      await _mount(
        tester,
        CameraPreviewWidget(
          controller: controller,
          autoStart: false,
          captureFactory: () => _capture(source),
          acquireHardware: () async => () async {
            released = true;
          },
        ),
      );
      try {
        await tester.runAsync(() async {
          await controller.resume();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          expect(source.running, isTrue);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          await controller.stop();
        });
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(source.running, isFalse);
        expect(released, isTrue);
        expect(source.starts, 1);
      } finally {
        await _close(tester, controller, source);
      }
    },
  );

  testWidgets(
    'batch captures multiple JPEGs in one camera session and releases on explicit stop',
    (tester) async {
      final source = _Source(), controller = CameraPreviewController();
      final photos = <Uint8List>[];
      var releases = 0;
      controller.onCaptured = (bytes) {
        expect(source.running, isTrue);
        photos.add(bytes);
      };
      await _mount(
        tester,
        CameraPreviewWidget(
          controller: controller,
          autoStart: false,
          captureMode: DocumentCameraCaptureMode.batch,
          captureFactory: () => _capture(source),
          acquireHardware: () async => () async {
            releases++;
          },
        ),
      );
      try {
        await tester.runAsync(() async {
          await controller.resume();
          for (var i = 0; i < 3; i++) {
            await controller.capture();
            expect(photos, hasLength(i + 1));
            expect(controller.isReady, isTrue);
          }
        });
        await tester.pump();
        expect(source.starts, 1);
        expect(releases, 0);
        expect(find.byType(DocumentCameraPreview), findsOneWidget);
        await tester.runAsync(controller.stop);
        expect(releases, 1);
        expect(source.running, isFalse);
      } finally {
        await _close(tester, controller, source);
      }
    },
  );

  testWidgets(
    'a rejected manual capture preserves preview and can retry without reopening',
    (tester) async {
      final source = _Source()..document = false;
      final controller = CameraPreviewController();
      var photos = 0;
      controller.onCaptured = (_) => photos++;
      await _mount(
        tester,
        CameraPreviewWidget(
          controller: controller,
          autoStart: false,
          captureFactory: () => _capture(source),
        ),
      );
      try {
        await tester.runAsync(() async {
          await controller.resume();
          await controller.capture();
        });
        await tester.pump();
        expect(photos, 0);
        expect(source.running, isTrue);
        expect(find.byType(DocumentCameraPreview), findsOneWidget);
        expect(find.textContaining('Chưa thấy đủ bốn góc'), findsOneWidget);
        source.document = true;
        await tester.runAsync(controller.capture);
        expect(photos, 1);
        expect(source.starts, 1);
      } finally {
        await _close(tester, controller, source);
      }
    },
  );

  testWidgets(
    'batch auto capture keeps the remove-document latch through rebuilds and cooldown',
    (tester) async {
      final source = _Source(), controller = CameraPreviewController();
      final capture = _capture(source);
      var photos = 0, sequence = 0;
      controller.onCaptured = (_) => photos++;
      CameraPreviewWidget preview() => CameraPreviewWidget(
        controller: controller,
        autoStart: false,
        enableAutoCapture: true,
        captureMode: DocumentCameraCaptureMode.batch,
        captureFactory: () => capture,
      );
      Future<void> feed({bool document = true}) async {
        await tester.runAsync(() async {
          source.framesController.add(
            fixture(document: document, sequence: ++sequence),
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: preview())));
      }

      await _mount(tester, preview());
      try {
        await tester.runAsync(controller.resume);
        for (var i = 0; i < 20 && photos == 0; i++) {
          await feed();
        }
        expect(photos, 1);
        for (var i = 0; i < 25; i++) {
          await feed();
        }
        expect(photos, 1);
        await feed(document: false);
        for (var i = 0; i < 20 && photos == 1; i++) {
          await feed();
        }
        expect(photos, 2);
        expect(source.starts, 1);
        expect(source.running, isTrue);
      } finally {
        await _close(tester, controller, source);
      }
    },
  );

  testWidgets(
    'new view waits for the previous unmounted view to release the camera',
    (tester) async {
      final source = _Source(),
          next = _Source(),
          controller = CameraPreviewController();
      await _mount(
        tester,
        CameraPreviewWidget(
          controller: controller,
          autoStart: false,
          captureFactory: () => _capture(source),
        ),
      );
      await tester.runAsync(() async {
        await controller.resume();
        source.stopGate = Completer<void>();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await _mount(
        tester,
        CameraPreviewWidget(
          controller: controller,
          autoStart: false,
          captureFactory: () => _capture(next),
        ),
      );
      try {
        late Future<void> starting;
        await tester.runAsync(() async {
          starting = controller.resume();
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(next.starts, 0);
          source.stopGate!.complete();
        });
        for (var i = 0; i < 200 && !next.running; i++) {
          // Unmount cleanup uses the widget zone; also drive real isolate I/O.
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(next.running, isTrue);
        await tester.runAsync(() => starting);
        expect(source.running, isFalse);
      } finally {
        if (!source.stopGate!.isCompleted) source.stopGate!.complete();
        await _close(tester, controller, next);
        await tester.runAsync(() => source.framesController.close());
      }
    },
  );
}
