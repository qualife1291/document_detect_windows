import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ffi_uvc/flutter_ffi_uvc.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'package:windows_doc_capture_uvc/windows_doc_capture_uvc.dart';

class Camera extends Fake implements UvcCamera {
  final events = StreamController<UvcStreamError>.broadcast();
  final order = <String>[];
  var copies = 0, created = 0, attached = 0, disposed = 0, sequence = 0;
  var failStart = false;
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
  Future<List<UvcUsbDevice>> listUsbDevices() async => [
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
  Future<void> openUsbDevice(int deviceId) async {}
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
  List<UvcCameraMode> supportedModes() => [
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
    return UvcPreviewFrame(
      width: mode.width,
      height: mode.height,
      rgbaBytes: Uint8List(mode.width * mode.height * 4),
      sequence: sequence,
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
  }

  @override
  Future<void> dispose() async {
    disposed++;
    order.add('camera_dispose');
  }
}

void main() {
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
      for (var i = 0; i < 30; i++) {
        expect(source.frames, same(frames));
        expect(
          (source.buildPreview() as RgbaCameraPreview).frames,
          same(frames),
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
      for (final fps in [0, 9, 121]) {
        expect(
          () => UvcFrameSource(preferredNativeFps: fps),
          throwsArgumentError,
        );
      }
    },
  );
}
