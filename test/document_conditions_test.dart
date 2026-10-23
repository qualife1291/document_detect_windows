import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:windows_doc_capture/windows_doc_capture.dart';

/// Synthetic printed rectangle; no real identity/medical information.
FrameBuffer documentScene({
  int width = 480,
  int height = 360,
  double ratio = 1.586,
  int paper = 190,
  int background = 35,
  bool texture = true,
  bool glare = false,
  bool shadow = false,
}) {
  final w = math.min(width * .76, height * .76 * ratio).round();
  final h = (w / ratio).round();
  final left = (width - w) ~/ 2, top = (height - h) ~/ 2;
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final inside = x >= left && x < left + w && y >= top && y < top + h;
      final sx = x * 480 ~/ width, sy = y * 360 ~/ height;
      var v = inside ? paper : background;
      if (inside && texture && sx % 17 < 3 && sy % 13 < 5) {
        v = math.max(0, v - 65);
      }
      if (inside && shadow) v = math.max(0, v - (55 * (x - left) / w).round());
      if (inside && glare && x > left + w * .55) v = 255;
      final i = (y * width + x) * 4;
      bytes[i] = v;
      bytes[i + 1] = v;
      bytes[i + 2] = v;
      bytes[i + 3] = 255;
    }
  }
  return FrameBuffer(
    width: width,
    height: height,
    rgba: bytes,
    capturedAt: DateTime.now(),
    sequence: 1,
  );
}

void main() {
  for (final shape in <String, double>{
    'ID / driver card landscape': 1.586,
    'legacy driver card': 1.42,
    'portrait ID': 1 / 1.586,
    'A4 medical form': 1 / 1.414,
    'square medical card': 1,
    'wide medical slip': 2.7,
  }.entries) {
    test(
      '${shape.key}: geometry under diffuse light and a mild shadow',
      () async {
        final detector = PureDartDocumentDetector();
        for (final shadow in [false, true]) {
          final frame = documentScene(ratio: shape.value, shadow: shadow);
          final result = await detector.detect(frame);
          expect(result.hasDocument, isTrue, reason: 'shadow=$shadow');
          expect(result.quad, hasLength(4));
          expect(result.edgeMargin, greaterThan(.05));
          expect(result.brightnessScore, inInclusiveRange(.35, .8));
        }
        detector.dispose();
      },
    );
  }
  for (final condition
      in <
            String,
            ({
              int paper,
              int background,
              bool texture,
              bool glare,
              WarningType warning,
            })
          >{
            'underexposure': (
              paper: 40,
              background: 0,
              texture: false,
              glare: false,
              warning: WarningType.tooDark,
            ),
            'overexposure': (
              paper: 255,
              background: 35,
              texture: false,
              glare: false,
              warning: WarningType.tooBright,
            ),
            'localized glare': (
              paper: 190,
              background: 35,
              texture: true,
              glare: true,
              warning: WarningType.tooBright,
            ),
            'defocused / no interior detail': (
              paper: 190,
              background: 35,
              texture: false,
              glare: false,
              warning: WarningType.blur,
            ),
          }
          .entries) {
    test(
      '${condition.key} blocks automatic capture for ID and medical form',
      () async {
        final c = condition.value;
        for (final ratio in [1.586, 1 / 1.414]) {
          final result = await PureDartDocumentDetector().detect(
            documentScene(
              ratio: ratio,
              paper: c.paper,
              background: c.background,
              texture: c.texture,
              glare: c.glare,
            ),
          );
          final warnings = const QualityThresholds().warningsFor(result);
          expect(warnings.map((w) => w.type), contains(c.warning));
          final auto = AutoCaptureController();
          for (var i = 0; i < 12; i++) {
            expect(
              auto.update(result, const [
                Offset(.1, .1),
                Offset(.9, .1),
                Offset(.9, .9),
                Offset(.1, .9),
              ], Duration(milliseconds: i * 100)),
              isFalse,
            );
          }
        }
      },
    );
  }
  test(
    'weak contrast is rejected and dark card on light background remains detectable',
    () async {
      final d = PureDartDocumentDetector();
      expect(
        (await d.detect(
          documentScene(paper: 100, background: 95, texture: false),
        )).hasDocument,
        isFalse,
      );
      final dark = await d.detect(documentScene(paper: 65, background: 210));
      expect(dark.hasDocument, isTrue);
      expect(dark.quad, hasLength(4));
    },
  );
  for (final size in [(2592, 1944), (3264, 2448)]) {
    test(
      '${size.$1}x${size.$2}: full resolution JPEG/crop and mapped corners',
      () async {
        final frame = documentScene(width: size.$1, height: size.$2);
        final result = await const CropPipeline(jpegQuality: 75).capture(frame);
        expect(result, isNotNull);
        final original = img.decodeJpg(result!.originalJpeg)!;
        expect(original.width, size.$1);
        expect(original.height, size.$2);
        final crop = img.decodeJpg(result.croppedJpeg)!;
        expect(crop.width, closeTo(size.$1 * .76, 20));
        expect(crop.width / crop.height, closeTo(1.586, .03));
        expect(result.quad.first.dx, closeTo(size.$1 * .12, 15));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
  test('8MP portrait frame is bounded by analysis longest dimension', () async {
    final frame = documentScene(width: 2448, height: 3264, ratio: 1 / 1.414);
    final result = await PureDartDocumentDetector().detect(frame);
    expect(result.hasDocument, isTrue);
    expect(result.quad, hasLength(4));
    expect(result.quad!.first.dy, greaterThan(100));
  });
}
