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
  bool running = false, document = true, failStop = false;
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
    if (failStop) throw StateError('Native cleanup failed');
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

Future<Object?> _driveWidgetFuture(
  WidgetTester tester,
  Future<void> work,
) async {
  var completed = false;
  Object? failure;
  unawaited(
    work.then<void>(
      (_) => completed = true,
      onError: (Object error, StackTrace _) {
        failure = error;
        completed = true;
      },
    ),
  );
  for (var i = 0; i < 500 && !completed; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(completed, isTrue, reason: 'Widget-zone lifecycle must finish');
  return failure;
}

void main() {
  testWidgets('camera stream error remains error until explicit recovery', (
    tester,
  ) async {
    final source = _Source(), controller = CameraPreviewController();
    final states = <DocumentPreviewState>[];
    await _mount(
      tester,
      CameraPreviewWidget(
        controller: controller,
        autoStart: false,
        captureFactory: () => _capture(source),
        onDocumentStateChanged: states.add,
      ),
    );
    try {
      await _driveWidgetFuture(tester, controller.resume());
      source.framesController.addError(StateError('Unplugged'));
      for (var i = 0; i < 20; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(source.running, isFalse);
      expect(states.last, DocumentPreviewState.error);
      expect(await _driveWidgetFuture(tester, controller.resume()), isNull);
      expect(source.running, isTrue);
      expect(states.last, DocumentPreviewState.processing);
    } finally {
      expect(await _driveWidgetFuture(tester, controller.shutdown()), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await source.framesController.close();
    }
  });

  testWidgets(
    'stopping while camera configuration waits reports idle and rejects late ready',
    (tester) async {
      final source = _Source(), controller = CameraPreviewController();
      final states = <DocumentPreviewState>[];
      late Completer<void> entered, configured;
      await _mount(
        tester,
        CameraPreviewWidget(
          controller: controller,
          autoStart: false,
          captureFactory: () => _capture(source),
          onDocumentStateChanged: states.add,
          configureCamera: (_) async {
            entered.complete();
            await configured.future;
          },
        ),
      );
      try {
        await tester.runAsync(() async {
          entered = Completer<void>();
          configured = Completer<void>();
          final starting = controller.resume();
          await entered.future;
          final stopping = controller.stop();
          expect(states.last, DocumentPreviewState.idle);
          configured.complete();
          await starting;
          await stopping;
        });
        expect(source.running, isFalse);
        expect(controller.isReady, isFalse);
        expect(
          states.where((s) => s == DocumentPreviewState.idle),
          hasLength(1),
        );
      } finally {
        await _close(tester, controller, source);
      }
    },
  );

  testWidgets(
    'idle callback can resume without starting before the previous camera closes',
    (tester) async {
      final source = _Source(), controller = CameraPreviewController();
      Future<void>? resumed;
      await _mount(
        tester,
        CameraPreviewWidget(
          controller: controller,
          autoStart: false,
          captureFactory: () => _capture(source),
          onDocumentStateChanged: (state) {
            if (state == DocumentPreviewState.idle) {
              resumed = controller.resume();
            }
          },
        ),
      );
      try {
        await tester.runAsync(() async {
          await controller.resume();
          source.stopGate = Completer<void>();
          final stopping = controller.stop();
          expect(resumed, isNotNull);
          expect(source.starts, 1);
          source.stopGate!.complete();
          source.stopGate = null;
          await stopping;
          await resumed;
        });
        expect(source.events, ['start', 'stop', 'start']);
        expect(source.running, isTrue);
      } finally {
        await _close(tester, controller, source);
      }
    },
  );

  testWidgets(
    'failed native stop retains the host lease until a verified retry',
    (tester) async {
      final source = _Source(), controller = CameraPreviewController();
      var releases = 0;
      await _mount(
        tester,
        CameraPreviewWidget(
          controller: controller,
          autoStart: false,
          captureFactory: () => _capture(source),
          acquireHardware: () async => () async {
            releases++;
          },
        ),
      );
      try {
        await tester.runAsync(controller.resume);
        source.failStop = true;
        await tester.runAsync(
          () => expectLater(controller.stop(), throwsStateError),
        );
        expect(source.running, isTrue);
        expect(releases, 0);
        await tester.runAsync(
          () => expectLater(controller.resume(), throwsStateError),
        );
        expect(releases, 0);
        expect(source.starts, 1);
        source.failStop = false;
        await tester.runAsync(controller.resume);
        expect(releases, 1);
        expect(source.running, isTrue);
        await tester.runAsync(controller.stop);
        expect(releases, 2);
        expect(source.running, isFalse);
      } finally {
        source.failStop = false;
        await _close(tester, controller, source);
      }
    },
  );

  testWidgets(
    'throwing idle callback cannot interrupt cleanup or hardware release',
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
          onDocumentStateChanged: (state) {
            if (state == DocumentPreviewState.idle) {
              throw StateError('Host callback');
            }
          },
        ),
      );
      try {
        await tester.runAsync(controller.resume);
        await tester.runAsync(controller.stop);
        expect(source.running, isFalse);
        expect(released, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, controller, source);
      }
    },
  );

  testWidgets('shutdown can retry failed cleanup after the view unmounts', (
    tester,
  ) async {
    final source = _Source(), controller = CameraPreviewController();
    await _mount(
      tester,
      CameraPreviewWidget(
        controller: controller,
        autoStart: false,
        captureFactory: () => _capture(source),
      ),
    );
    // Unmount runs in this widget error zone; keep failed cleanup futures in it.
    expect(await _driveWidgetFuture(tester, controller.resume()), isNull);
    source.failStop = true;
    await tester.pumpWidget(const SizedBox.shrink());
    try {
      expect(
        await _driveWidgetFuture(tester, controller.shutdown()),
        isA<StateError>(),
      );
      source.failStop = false;
      expect(await _driveWidgetFuture(tester, controller.shutdown()), isNull);
      expect(source.running, isFalse);
      expect(controller.isAttached, isFalse);
    } finally {
      source.failStop = false;
      expect(await _driveWidgetFuture(tester, controller.shutdown()), isNull);
      await source.framesController.close();
    }
  });

  testWidgets('explicit stop reports idle to the host after preview', (
    tester,
  ) async {
    final source = _Source(), controller = CameraPreviewController();
    final states = <DocumentPreviewState>[];
    await _mount(
      tester,
      CameraPreviewWidget(
        controller: controller,
        autoStart: false,
        captureFactory: () => _capture(source),
        onDocumentStateChanged: states.add,
      ),
    );
    try {
      await tester.runAsync(controller.resume);
      expect(states, contains(DocumentPreviewState.processing));
      await tester.runAsync(controller.stop);
      expect(states.last, DocumentPreviewState.idle);
      expect(source.running, isFalse);
    } finally {
      await _close(tester, controller, source);
    }
  });

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
    'preview sizes itself inside a Column without an explicit height',
    (tester) async {
      final source = _Source(), controller = CameraPreviewController();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 320,
                  child: CameraPreviewWidget(
                    controller: controller,
                    autoStart: false,
                    captureFactory: () => _capture(source),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      try {
        await tester.runAsync(controller.resume);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(DocumentCameraPreview)),
          const Size(320, 240),
        );
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
