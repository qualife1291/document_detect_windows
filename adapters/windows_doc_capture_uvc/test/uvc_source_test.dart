import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture_uvc_backend/windows_doc_capture_uvc_backend.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'package:windows_doc_capture_uvc/windows_doc_capture_uvc.dart';

class Camera extends Fake implements UvcCamera {
  final events = StreamController<UvcStreamError>.broadcast();
  final order = <String>[];
  var copies = 0, created = 0, attached = 0, disposed = 0, sequence = 0;
  var failStart = false, failDispose = false, failTexture = false;
  Duration copyWork = Duration.zero;
  void Function()? afterSample;
  List<UvcCameraMode>? modesOverride;
  List<UvcUsbDevice>? devicesOverride;
  final openedDeviceIds = <int>[];
  UvcCameraMode mode = const UvcCameraMode(
    frameFormat: 1,
    formatName: 'synthetic',
    width: 1280,
    height: 720,
    fps: 30,
  );
  @override
  void setLogLevel(UvcLogLevel level) {}
  @override
  Future<List<UvcUsbDevice>> listUsbDevices() async =>
      devicesOverride ??
      [
        const UvcUsbDevice(
          deviceId: 1,
          deviceName: 'test',
          vendorId: 0,
          productId: 0,
          productName: 'test',
          manufacturerName: 'test',
          serialNumber: '',
          hasPermission: true,
        ),
      ];
  @override
  Future<void> openUsbDevice(int deviceId) async {
    openedDeviceIds.add(deviceId);
  }

  @override
  Stream<UvcStreamError> get streamErrors => events.stream;
  @override
  Future<int> createPreviewTexture() async {
    created++;
    return 42;
  }

  @override
  Future<void> attachPreviewTexture(
    int textureId, {
    int? width,
    int? height,
  }) async {
    attached++;
  }

  @override
  List<UvcCameraMode> supportedModes() =>
      modesOverride ??
      [
        mode,
        const UvcCameraMode(
          frameFormat: 1,
          formatName: 'synthetic',
          width: 1280,
          height: 720,
          fps: 15,
        ),
      ];
  @override
  Future<UvcAutoPreviewResult> startPreviewAuto({
    List<UvcCameraMode>? candidates,
    UvcAutoPreviewPreference preference = UvcAutoPreviewPreference.reliability,
    UvcPreviewPolicy policy = UvcPreviewPolicy.stableFrames,
    int consecutiveValidFrames = 3,
    Duration perModeTimeout = const Duration(seconds: 2),
    int maxCandidates = 8,
  }) async {
    mode = candidates!.first;
    return UvcAutoPreviewResult(
      attempts: [
        UvcPreviewStartResult(
          mode: mode,
          success: !failStart,
          validFrameCount: 3,
          consecutiveValidFrames: 3,
          errorCount: 0,
          elapsed: Duration.zero,
        ),
      ],
    );
  }

  @override
  int latestFrameSequence() => ++sequence;
  @override
  UvcPreviewFrame? copyLatestFrame() {
    copies++;
    fullCopies++;
    final work = Stopwatch()..start();
    while (work.elapsed < copyWork) {
      /* deterministic native readback cost */
    }
    return UvcPreviewFrame(
      width: mode.width,
      height: mode.height,
      rgbaBytes: Uint8List(mode.width * mode.height * 4),
      sequence: sequence,
    );
  }

  int fullCopies = 0;
  final requestedSamples = <(int, int)>[];
  @override
  UvcSampledFrames? copyLatestSampledFrames({
    int analysisMaxDimension = 0,
    int previewMaxDimension = 0,
  }) {
    requestedSamples.add((analysisMaxDimension, previewMaxDimension));
    copies++;
    final work = Stopwatch()..start();
    while (work.elapsed < copyWork) {
      /* native sampling cost */
    }
    UvcPreviewFrame? sample(int maximum) {
      if (maximum == 0) return null;
      final scale = maximum < mode.width ? maximum / mode.width : 1.0;
      final w = (mode.width * scale).round(), h = (mode.height * scale).round();
      return UvcPreviewFrame(
        width: w,
        height: h,
        rgbaBytes: Uint8List(w * h * 4),
        sequence: sequence,
      );
    }

    afterSample?.call();
    return UvcSampledFrames(
      analysis: sample(analysisMaxDimension),
      preview: sample(previewMaxDimension),
    );
  }

  @override
  UvcStreamStats getStreamStats() => const UvcStreamStats.zero();
  @override
  Future<void> stopPreview() async {
    order.add('stop');
  }

  @override
  Future<void> disposePreviewTexture(int textureId) async {
    order.add('texture_dispose');
    if (failTexture) throw StateError('Texture still registered');
  }

  @override
  Future<void> dispose() async {
    disposed++;
    order.add('camera_dispose');
    if (failDispose) throw StateError('Native teardown not queued');
  }
}

UvcUsbDevice namedDevice(int id, String path) => UvcUsbDevice(
  deviceId: id,
  deviceName: path,
  vendorId: 0,
  productId: 0,
  productName: 'Synthetic camera',
  manufacturerName: '',
  serialNumber: '',
  hasPermission: true,
);

Camera smallCamera() => Camera()
  ..modesOverride = [
    const UvcCameraMode(
      frameFormat: 1,
      formatName: 'synthetic',
      width: 64,
      height: 48,
      fps: 30,
    ),
  ];

Future<ui.Image> previewImage() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const Color(0xff336699), ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(8, 8);
  } finally {
    picture.dispose();
  }
}

Future<void> advance(WidgetTester tester, int milliseconds) async {
  final end = DateTime.now().add(Duration(milliseconds: milliseconds));
  while (DateTime.now().isBefore(end)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

void main() {
  test(
    'saved camera path survives numeric ID and enumeration order changes',
    () async {
      final camera = Camera()
        ..devicesOverride = [
          namedDevice(1, r'\\?\USB#DOC#GLOBAL'),
          namedDevice(2, r'\\?\USB#FACE#GLOBAL'),
        ];
      final source = UvcFrameSource.testing(
        camera: camera,
        previewMode: UvcPreviewMode.bitmap,
      );
      try {
        final saved = (await source.listDevices()).first.id;
        camera.devicesOverride = [
          namedDevice(1, r'\\?\USB#FACE#GLOBAL'),
          namedDevice(77, r'\\?\USB#DOC#GLOBAL'),
        ];
        await source.start(deviceId: saved.toUpperCase());
        expect(camera.openedDeviceIds, [77]);
      } finally {
        await source.stop();
        await camera.events.close();
      }
    },
  );

  test(
    'legacy numeric selection fails closed instead of opening another camera',
    () async {
      final camera = Camera()
        ..devicesOverride = [
          namedDevice(1, r'\\?\USB#FACE#GLOBAL'),
          namedDevice(2, r'\\?\USB#DOC#GLOBAL'),
        ];
      final source = UvcFrameSource.testing(camera: camera);
      try {
        await expectLater(source.start(deviceId: '1'), throwsStateError);
        expect(camera.openedDeviceIds, isEmpty);
      } finally {
        await source.stop();
        await camera.events.close();
      }
    },
  );

  test('failed native disposal keeps its handle for stop retry', () async {
    final camera = Camera();
    final source = UvcFrameSource.testing(
      camera: camera,
      previewMode: UvcPreviewMode.bitmap,
    );
    try {
      await source.start();
      camera.failDispose = true;
      await expectLater(source.stop(), throwsStateError);
      expect(await source.latestFullResolutionFrame(), isNull);
      expect(camera.fullCopies, 0);
      camera.failDispose = false;
      await source.stop();
      expect(camera.disposed, 2);
      expect(source.previewSize, Size.zero);
    } finally {
      camera.failDispose = false;
      await source.stop();
      await camera.events.close();
    }
  });

  test(
    'failed texture cleanup retries unregister after native disposal',
    () async {
      final camera = Camera();
      final source = UvcFrameSource.testing(camera: camera);
      try {
        await source.start();
        camera.failTexture = true;
        await expectLater(source.stop(), throwsStateError);
        camera.failTexture = false;
        await source.stop();
        expect(camera.order.where((e) => e == 'texture_dispose'), hasLength(2));
      } finally {
        camera.failTexture = false;
        await source.stop();
        await camera.events.close();
      }
    },
  );

  test(
    'failed enumeration disposal is retried before a new camera operation',
    () async {
      final camera = Camera()..failDispose = true;
      final source = UvcFrameSource.testing(camera: camera);
      try {
        await expectLater(source.listDevices(), throwsStateError);
        camera.failDispose = false;
        await source.stop();
        expect(camera.disposed, 2);
      } finally {
        camera.failDispose = false;
        await source.stop();
        await camera.events.close();
      }
    },
  );

  testWidgets(
    'profiles bound 8MP samples while snapshots retain every native pixel',
    (tester) async {
      final seed = (await tester.runAsync(previewImage))!;
      for (final entry in [
        (BitmapPreviewProfile.lowResource, 640),
        (BitmapPreviewProfile.balanced, 960),
        (BitmapPreviewProfile.detail, 1280),
      ]) {
        final camera = Camera()
          ..modesOverride = [
            const UvcCameraMode(
              frameFormat: 1,
              formatName: 'synthetic',
              width: 3264,
              height: 2448,
              fps: 15,
            ),
          ];
        final source = UvcFrameSource.testing(
          camera: camera,
          previewMode: UvcPreviewMode.bitmap,
          bitmapPreviewProfile: entry.$1,
          pollInterval: const Duration(milliseconds: 200),
        );
        source.analysisWanted = () => true;
        final received = <FrameBuffer>[];
        final sub = source.frames.listen(received.add);
        await tester.runAsync(
          () => source.start(preset: ResolutionPreset.veryHigh),
        );
        final built = source.buildPreview() as RgbaCameraPreview;
        try {
          await tester.pumpWidget(
            RgbaCameraPreview.testing(
              frames: built.frames,
              maxDimension: 1280,
              frameDemand: built.frameDemand,
              decodeFrame: (_) => Future.value(seed.clone()),
            ),
          );
          await advance(tester, 220);
          expect(camera.fullCopies, 0);
          expect(received, isNotEmpty);
          for (final frame in received) {
            expect(frame.width, 640);
            expect(frame.height, 480);
          }
          final metrics = source.bitmapPreviewMetrics!;
          expect(metrics.previewWidth, entry.$2);
          expect(metrics.previewHeight, entry.$2 * 3 ~/ 4);
          source.analysisWanted = () => false;
          source.previewSamplingAllowed = () => false;
          final snapshot = (await tester.runAsync(
            source.latestFullResolutionFrame,
          ))!;
          expect(snapshot.width, 3264);
          expect(snapshot.height, 2448);
          expect(camera.fullCopies, 1);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await sub.cancel();
            await source.stop();
            await camera.events.close();
          });
        }
      }
      seed.dispose();
    },
  );

  testWidgets('10ms readback preserves cadence without full preview copies', (
    tester,
  ) async {
    var elapsed = Duration.zero;
    final camera = smallCamera()
      ..afterSample = () {
        elapsed += const Duration(milliseconds: 10);
      };
    final source = UvcFrameSource.testing(
      camera: camera,
      samplingClock: () => elapsed,
      automaticPolling: false,
      previewMode: UvcPreviewMode.bitmap,
      pollInterval: const Duration(milliseconds: 200),
    );
    source.analysisWanted = () => false;
    final seed = (await tester.runAsync(previewImage))!;
    await tester.runAsync(source.start);
    final built = source.buildPreview() as RgbaCameraPreview;
    try {
      await tester.pumpWidget(
        RgbaCameraPreview.testing(
          frames: built.frames,
          frameDemand: built.frameDemand,
          decodeFrame: (_) => Future.value(seed.clone()),
        ),
      );
      // Model 16ms scheduler slots, with 10ms native work in each due period.
      // Counting from completion would miss every second 64ms slot (7 vs13).
      for (var slot = 0; slot <= 12; slot++) {
        elapsed = Duration(milliseconds: slot * 64);
        source.pollForTesting();
        await tester.pump();
      }
      final metrics = source.bitmapPreviewMetrics!;
      expect(metrics.offeredFrames, 13);
      expect(metrics.totalSamplingTime, const Duration(milliseconds: 130));
      expect(metrics.lastOfferedAt, const Duration(milliseconds: 778));
      expect(camera.fullCopies, 0);
      expect(
        camera.requestedSamples.every((r) => r.$1 == 0 && r.$2 == 960),
        isTrue,
      );
      source.previewSamplingAllowed = () => false;
      final full = (await tester.runAsync(source.latestFullResolutionFrame))!;
      expect(camera.fullCopies, 1);
      expect(full.width, camera.mode.width);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await source.stop();
        await camera.events.close();
      });
      seed.dispose();
    }
  });
  test('frame stream identity survives repeated preview builds', () async {
    final camera = Camera();
    final source = UvcFrameSource.testing(
      camera: camera,
      previewMode: UvcPreviewMode.bitmap,
    );
    source.analysisWanted = () => false;
    try {
      await source.start();
      final frames = source.frames;
      final preview = (source.buildPreview() as RgbaCameraPreview).frames;
      expect(preview, isNot(same(frames)));
      for (var i = 0; i < 30; i++) {
        expect(source.frames, same(frames));
        expect(
          (source.buildPreview() as RgbaCameraPreview).frames,
          same(preview),
        );
      }
    } finally {
      await source.stop();
      await camera.events.close();
    }
  });
  testWidgets(
    'bitmap keeps the decoded frame across status and parent rebuilds',
    (tester) async {
      final camera = Camera();
      final source = UvcFrameSource.testing(
        camera: camera,
        previewMode: UvcPreviewMode.bitmap,
      );
      final status = ValueNotifier(
        DocumentPreviewStatus(state: DocumentPreviewState.processing),
      );
      var wanted = true;
      source.analysisWanted = () => wanted;
      source.previewSamplingAllowed = () => wanted;
      await tester.runAsync(source.start);
      Widget tree() => Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 640,
          height: 360,
          child: DocumentCameraPreview(frameSource: source, status: status),
        ),
      );
      try {
        await tester.pumpWidget(tree());
        await tester.pump(const Duration(milliseconds: 100));
        for (
          var i = 0;
          i < 100 &&
              tester.widget<RawImage>(find.byType(RawImage)).image == null;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        wanted = false;
        final image = tester.widget<RawImage>(find.byType(RawImage)).image;
        expect(image, isNotNull);
        for (var i = 0; i < 30; i++) {
          status.value = DocumentPreviewStatus(
            state: i.isEven
                ? DocumentPreviewState.clear
                : DocumentPreviewState.noDocument,
          );
          await tester.pumpWidget(tree());
          expect(
            tester.widget<RawImage>(find.byType(RawImage)).image,
            same(image),
          );
          expect(image!.debugDisposed, isFalse);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        expect(image!.debugDisposed, isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await source.stop();
          await camera.events.close();
        });
        status.dispose();
      }
    },
  );
  testWidgets(
    'bitmap cadence is independent of analysis and shares sampled frames',
    (tester) async {
      final camera = smallCamera();
      final source = UvcFrameSource.testing(
        camera: camera,
        previewMode: UvcPreviewMode.bitmap,
        pollInterval: const Duration(milliseconds: 200),
      );
      final analysis = <FrameBuffer>[], preview = <FrameBuffer>[];
      final seed = (await tester.runAsync(previewImage))!;
      source.analysisWanted = () => true;
      final analysisSub = source.frames.listen(analysis.add);
      await tester.runAsync(source.start);
      final built = source.buildPreview() as RgbaCameraPreview;
      final previewSub = built.frames.listen(preview.add);
      try {
        await tester.pumpWidget(
          RgbaCameraPreview.testing(
            frames: built.frames,
            frameDemand: built.frameDemand,
            decodeFrame: (_) => Future.value(seed.clone()),
          ),
        );
        await advance(tester, 1000);
        expect(analysis.length, inInclusiveRange(3, 6));
        expect(preview.length, greaterThan(analysis.length * 1.5));
        expect(preview.length, lessThanOrEqualTo(18));
        expect(camera.copies, lessThan(analysis.length + preview.length));
        expect(
          analysis.any((a) => preview.any((p) => a.sequence == p.sequence)),
          isTrue,
        );
        source.previewSamplingAllowed = () => false;
        source.analysisWanted = () => false;
        final snapshot = (await tester.runAsync(
          source.latestFullResolutionFrame,
        ))!;
        expect(snapshot.width, 64);
        expect(source.bitmapPreviewMetrics!.offeredFrames, preview.length);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await analysisSub.cancel();
          await previewSub.cancel();
          await source.stop();
          await camera.events.close();
        });
        seed.dispose();
      }
    },
  );
  testWidgets(
    'paused, busy and unmounted bitmap consumers prevent extra copies',
    (tester) async {
      final camera = smallCamera();
      final source = UvcFrameSource.testing(
        camera: camera,
        previewMode: UvcPreviewMode.bitmap,
      );
      source.analysisWanted = () => false;
      var allowed = false;
      source.previewSamplingAllowed = () => allowed;
      await tester.runAsync(source.start);
      final built = source.buildPreview() as RgbaCameraPreview;
      final gate = Completer<ui.Image>();
      try {
        await tester.pumpWidget(
          RgbaCameraPreview.testing(
            frames: built.frames,
            frameDemand: built.frameDemand,
            decodeFrame: (_) => gate.future,
          ),
        );
        await advance(tester, 150);
        expect(camera.copies, 0);
        allowed = true;
        await advance(tester, 150);
        expect(camera.copies, 1);
        expect(built.frameDemand!.canAcceptFrame, isFalse);
        await advance(tester, 200);
        expect(camera.copies, 1);
        allowed = false;
        final image = (await tester.runAsync(previewImage))!;
        gate.complete(image);
        await tester.pumpAndSettle();
        await advance(tester, 100);
        expect(camera.copies, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        allowed = true;
        await advance(tester, 100);
        expect(camera.copies, 1);
        expect(image.debugDisposed, isTrue);
        expect(built.frameDemand!.canAcceptFrame, isFalse);
        await tester.runAsync(() async {
          await source.stop();
          await source.start();
        });
        final next = source.buildPreview() as RgbaCameraPreview;
        expect(next.frameDemand, isNot(same(built.frameDemand)));
        final nextGate = Completer<ui.Image>();
        await tester.pumpWidget(
          RgbaCameraPreview.testing(
            frames: next.frames,
            frameDemand: next.frameDemand,
            decodeFrame: (_) => nextGate.future,
          ),
        );
        expect(next.frameDemand!.canAcceptFrame, isTrue);
        await advance(tester, 100);
        expect(next.frameDemand!.canAcceptFrame, isFalse);
        expect(built.frameDemand!.canAcceptFrame, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        final late = (await tester.runAsync(previewImage))!;
        nextGate.complete(late);
        await tester.pump();
        expect(late.debugDisposed, isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await source.stop();
          await camera.events.close();
        });
      }
    },
  );
  testWidgets('costly bitmap readback backs off without accumulating work', (
    tester,
  ) async {
    final camera = smallCamera()..copyWork = const Duration(milliseconds: 60);
    final source = UvcFrameSource.testing(
      camera: camera,
      previewMode: UvcPreviewMode.bitmap,
    );
    source.analysisWanted = () => false;
    final seed = (await tester.runAsync(previewImage))!;
    await tester.runAsync(source.start);
    final built = source.buildPreview() as RgbaCameraPreview;
    try {
      await tester.pumpWidget(
        RgbaCameraPreview.testing(
          frames: built.frames,
          frameDemand: built.frameDemand,
          decodeFrame: (_) => Future.value(seed.clone()),
        ),
      );
      await advance(tester, 650);
      final metrics = source.bitmapPreviewMetrics!;
      expect(
        metrics.maxSamplingTime,
        greaterThanOrEqualTo(const Duration(milliseconds: 60)),
      );
      expect(
        metrics.effectiveInterval,
        greaterThanOrEqualTo(const Duration(milliseconds: 300)),
      );
      expect(metrics.offeredFrames, inInclusiveRange(1, 6));
      expect(camera.copies, metrics.offeredFrames);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await source.stop();
        await camera.events.close();
      });
      seed.dispose();
    }
  });
  test(
    'bitmap start does not register external textures; demand gates copies and snapshots stay full size',
    () async {
      final camera = Camera();
      final source = UvcFrameSource.testing(
        camera: camera,
        previewMode: UvcPreviewMode.bitmap,
        preferredNativeFps: 15,
      );
      source.analysisWanted = () => false;
      try {
        await source.start();
        expect(camera.mode.fps, 15);
        expect(source.buildPreview(), isA<RgbaCameraPreview>());
        expect(camera.created, 0);
        expect(camera.attached, 0);
        await Future<void>.delayed(const Duration(milliseconds: 220));
        expect(camera.copies, 0);
        final snapshot = (await source.latestFullResolutionFrame())!;
        expect(snapshot.width, 1280);
        expect(snapshot.height, 720);
        source.analysisWanted = () => true;
        final frame = await source.frames.first.timeout(
          const Duration(seconds: 2),
        );
        expect(frame.width, 640);
        expect(frame.height, 360);
        await source.listDevices();
        expect(camera.disposed, 0);
      } finally {
        await source.stop();
        await camera.events.close();
      }
      expect(camera.disposed, 1);
      expect(source.previewSize, Size.zero);
      expect(camera.order, ['stop', 'camera_dispose']);
    },
  );
  test(
    'texture mode keeps native preview and releases it after stopping stream',
    () async {
      final camera = Camera();
      final source = UvcFrameSource.testing(camera: camera);
      source.analysisWanted = () => false;
      try {
        await source.start();
        expect(camera.mode.fps, 30);
        expect(source.buildPreview(), isA<Texture>());
        expect(camera.created, 1);
        expect(camera.attached, 1);
      } finally {
        await source.stop();
        await camera.events.close();
      }
      expect(camera.order, ['stop', 'texture_dispose', 'camera_dispose']);
    },
  );
  test(
    'failed starts release resources in either preview mode and permit a retry',
    () async {
      for (final mode in UvcPreviewMode.values) {
        final camera = Camera()..failStart = true;
        final source = UvcFrameSource.testing(
          camera: camera,
          previewMode: mode,
        );
        source.analysisWanted = () => false;
        try {
          await expectLater(source.start(), throwsStateError);
          expect(camera.disposed, 1);
          expect(source.previewSize, Size.zero);
          camera.failStart = false;
          await source.start();
          expect(source.previewSize, const Size(1280, 720));
        } finally {
          await source.stop();
          await camera.events.close();
        }
        expect(camera.disposed, 2);
      }
    },
  );
  test(
    'poll interval and preferred FPS reject unbounded sampling configuration',
    () {
      for (final duration in [
        Duration.zero,
        const Duration(milliseconds: 49),
        const Duration(seconds: 2),
      ]) {
        expect(
          () => UvcFrameSource(pollInterval: duration),
          throwsArgumentError,
        );
      }
      for (final duration in [
        Duration.zero,
        const Duration(milliseconds: 49),
        const Duration(seconds: 2),
      ]) {
        expect(
          () => UvcFrameSource(bitmapPreviewInterval: duration),
          throwsArgumentError,
        );
      }
      for (final fps in [0, 9, 121]) {
        expect(
          () => UvcFrameSource(preferredNativeFps: fps),
          throwsArgumentError,
        );
      }
    },
  );
}
