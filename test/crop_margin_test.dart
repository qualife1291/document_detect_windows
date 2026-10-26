import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'package:windows_doc_capture/src/capture/crop_geometry.dart';
import 'package:windows_doc_capture/src/detection/geometry.dart';
import 'fixtures.dart';

void main() {
  test(
    'default margin retains edge glyphs with a one-pixel inward detection error',
    () {
      final image = img.Image(width: 200, height: 140);
      img.fillRect(
        image,
        x1: 30,
        y1: 25,
        x2: 170,
        y2: 115,
        color: img.ColorUint8.rgb(220, 220, 220),
      );
      final ink = img.ColorUint8.rgb(255, 0, 255);
      img.drawLine(image, x1: 30, y1: 54, x2: 30, y2: 64, color: ink);
      img.drawLine(image, x1: 170, y1: 80, x2: 170, y2: 90, color: ink);
      img.drawLine(image, x1: 74, y1: 25, x2: 84, y2: 25, color: ink);
      img.drawLine(image, x1: 111, y1: 115, x2: 121, y2: 115, color: ink);
      const estimated = [
        Offset(31, 26),
        Offset(169, 26),
        Offset(169, 114),
        Offset(31, 114),
      ];
      List<int> glyphs(img.Image crop) {
        final counts = [0, 0, 0, 0];
        for (final p in crop) {
          if (p.r > 180 && p.b > 180 && p.g < 100) {
            if (p.x < 3) counts[0]++;
            if (p.x > crop.width - 4) counts[1]++;
            if (p.y < 3) counts[2]++;
            if (p.y > crop.height - 4) counts[3]++;
          }
        }
        return counts;
      }

      expect(glyphs(warpPerspective(image, estimated)), [0, 0, 0, 0]);
      final geometry = CropGeometry.fromDetection(
        estimated,
        width: image.width,
        height: image.height,
        padding: const CropPipeline().cropPadding,
      );
      expect(
        glyphs(warpPerspective(image, geometry.quad)),
        everyElement(greaterThanOrEqualTo(8)),
      );
      expect(geometry.paddingLimited, isFalse);
    },
  );
  for (final entry in <String, List<Offset>>{
    'perspective': [
      const Offset(30, 20),
      const Offset(180, 40),
      const Offset(160, 130),
      const Offset(20, 110),
    ],
    'rotated portrait': [
      const Offset(80, 20),
      const Offset(140, 60),
      const Offset(90, 140),
      const Offset(30, 100),
    ],
  }.entries) {
    test(
      '${entry.key}: margin encloses all detected corners and preserves edge directions',
      () {
        final q = entry.value;
        final result = CropGeometry.fromDetection(
          q,
          width: 220,
          height: 180,
          padding: .02,
        );
        expect(polygonArea(result.quad), greaterThan(polygonArea(q)));
        for (var i = 0; i < 4; i++) {
          final edge = q[(i + 1) % 4] - q[i];
          final expandedEdge = result.quad[(i + 1) % 4] - result.quad[i];
          expect(
            (edge.dx * expandedEdge.dy - edge.dy * expandedEdge.dx).abs(),
            lessThan(1e-7),
          );
          for (final p in q) {
            expect(
              cross(result.quad[i], result.quad[(i + 1) % 4], p),
              greaterThanOrEqualTo(-1e-7),
            );
          }
        }
      },
    );
  }
  test(
    'sensor boundary limits the margin uniformly without clipping the quad inward',
    () {
      const q = [Offset(1, 20), Offset(70, 20), Offset(70, 80), Offset(1, 80)];
      final result = CropGeometry.fromDetection(
        q,
        width: 100,
        height: 100,
        padding: .1,
      );
      expect(result.paddingLimited, isTrue);
      expect(result.requestedPaddingPixels, 6);
      expect(result.appliedPaddingPixels, closeTo(1, 1e-8));
      expect(result.quad, const [
        Offset(0, 19),
        Offset(71, 19),
        Offset(71, 81),
        Offset(0, 81),
      ]);
      final crop = warpPerspective(
        img.Image(width: 100, height: 100),
        result.quad,
      );
      // Exact aligned corners include both boundary pixels (0 through 71).
      expect(crop.width, 72);
      final touching = [
        const Offset(0, 20),
        ...q.skip(1).take(2),
        const Offset(0, 80),
      ];
      final atEdge = CropGeometry.fromDetection(
        touching,
        width: 100,
        height: 100,
        padding: .02,
      );
      expect(atEdge.appliedPaddingPixels, 0);
      expect(atEdge.quad, touching);
    },
  );
  test(
    'margin is resolution independent for 720p, 5MP and 8MP source coordinates',
    () {
      for (final size in [(1280, 720), (2592, 1944), (3264, 2448)]) {
        final w = size.$1.toDouble(), h = size.$2.toDouble();
        final q = [
          Offset(w * .2, h * .2),
          Offset(w * .8, h * .2),
          Offset(w * .8, h * .8),
          Offset(w * .2, h * .8),
        ];
        final geometry = CropGeometry.fromDetection(
          q,
          width: size.$1,
          height: size.$2,
          padding: .02,
        );
        expect(geometry.appliedPaddingPixels / h, closeTo(.012, 1e-10));
        expect(geometry.quad[0].dx / w, closeTo(.2 - .012 * h / w, 1e-10));
      }
    },
  );
  test(
    'zero margin preserves exact geometry and immutable returned corners',
    () {
      final q = List<Offset>.of(normalized.map((p) => p * 100));
      final geometry = CropGeometry.fromDetection(
        q,
        width: 120,
        height: 120,
        padding: 0,
      );
      expect(geometry.quad, q);
      q[0] = Offset.zero;
      expect(geometry.quad.first, const Offset(10, 10));
      expect(() => geometry.quad[0] = Offset.zero, throwsUnsupportedError);
    },
  );
  test(
    'invalid margin fails before worker processing and invalid geometry is rejected',
    () async {
      for (final value in [-.01, .10001, double.nan, double.infinity]) {
        await expectLater(
          CropPipeline(cropPadding: value).capture(fixture()),
          throwsArgumentError,
        );
      }
      for (final q in <List<Offset>>[
        const [],
        [const Offset(-1, 10), ...normalized.skip(1)],
        const [Offset(10, 10), Offset(80, 80), Offset(80, 10), Offset(10, 80)],
        const [
          Offset(double.nan, 10),
          Offset(80, 10),
          Offset(80, 80),
          Offset(10, 80),
        ],
      ]) {
        expect(
          () => CropGeometry.fromDetection(
            q,
            width: 100,
            height: 100,
            padding: .02,
          ),
          throwsArgumentError,
        );
      }
    },
  );
  test(
    'capture preserves original/detected quad, exposes actual crop quad and logs margin',
    () async {
      final frame = fixture();
      final detected = await PureDartDocumentDetector().detect(frame);
      final expected = detected.quad!
          .map((p) => Offset(p.dx / frame.width, p.dy / frame.height))
          .toList();
      Map<String, Object?>? diagnostic;
      final padded = (await const CropPipeline().capture(
        frame,
        requiredQuality: const QualityThresholds(),
        expectedNormalizedQuad: expected,
        maximumMotion: 1e-8,
        onDiagnostic: (event, fields) {
          diagnostic = fields;
        },
      ))!;
      final exact = (await const CropPipeline(cropPadding: 0).capture(frame))!;
      expect(padded.originalJpeg, orderedEquals(exact.originalJpeg));
      expect(padded.quad, exact.quad);
      expect(exact.cropQuad, exact.quad);
      expect(
        polygonArea(padded.cropQuad),
        greaterThan(polygonArea(padded.quad)),
      );
      expect(
        img.decodeJpg(padded.croppedJpeg)!.width,
        greaterThan(img.decodeJpg(exact.croppedJpeg)!.width),
      );
      expect(diagnostic!['decision'], 'accepted');
      expect(diagnostic!['cropPadding'], .02);
      expect(diagnostic!['paddingAppliedPx'], greaterThan(0));
      expect(diagnostic!['paddingLimited'], isFalse);
      final logged = diagnostic!['cropQuad']! as List;
      expect(logged[0], [
        padded.cropQuad[0].dx / frame.width,
        padded.cropQuad[0].dy / frame.height,
      ]);
      expect(() => padded.cropQuad[0] = Offset.zero, throwsUnsupportedError);
      final legacy = CapturedDocument(
        originalJpeg: padded.originalJpeg,
        croppedJpeg: exact.croppedJpeg,
        quad: exact.quad,
        blurScore: 0,
        coverageRatio: 0,
        capturedAt: frame.capturedAt,
      );
      expect(legacy.cropQuad, legacy.quad);
    },
  );
}
