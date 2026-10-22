import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'fixtures.dart';

void main() {
  test('detects A4 geometry, exposure and sharpness inside ROI', () async {
    final d = PureDartDocumentDetector();
    final r = await d.detect(fixture());
    expect(r.hasDocument, isTrue);
    expect(r.quad, hasLength(4));
    expect(r.coverageRatio, closeTo(.41, .03));
    expect(r.edgeMargin, greaterThan(.15));
    expect(r.tiltAngle, lessThan(2));
    expect(r.brightnessScore, inInclusiveRange(.65, .8));
    expect(r.blurScore, greaterThan(100));
    expect(r.kind, DocumentKind.a4);
  });
  test('rejects blank frame and small objects', () async {
    final d = PureDartDocumentDetector();
    expect((await d.detect(fixture(document: false))).hasDocument, isFalse);
    expect(
      (await d.detect(
        fixture(
          quad: const [
            Offset(10, 10),
            Offset(30, 10),
            Offset(30, 22),
            Offset(10, 22),
          ],
        ),
      )).hasDocument,
      isFalse,
    );
  });
  test(
    'perspective quadrilateral retains distinct corners and detects tilt',
    () async {
      final r = await PureDartDocumentDetector().detect(
        fixture(
          quad: const [
            Offset(65, 40),
            Offset(260, 65),
            Offset(240, 200),
            Offset(35, 170),
          ],
        ),
      );
      expect(r.hasDocument, isTrue);
      expect(r.quad![0].dx, closeTo(65, 5));
      expect(r.quad![1].dy, closeTo(65, 5));
      expect(r.tiltAngle, greaterThan(5));
    },
  );
  test('maps downsampled detector coordinates back to full pixels', () async {
    final r = await PureDartDocumentDetector(
      maxWidth: 160,
    ).detect(fixture(width: 1280, height: 960));
    expect(r.hasDocument, isTrue);
    expect(r.quad![0].dx, closeTo(1280 * .18, 18));
    expect(r.quad![2].dy, closeTo(960 * .82, 18));
  });
  test(
    'textureless paper does not inherit sharpness from its outside border',
    () async {
      final r = await PureDartDocumentDetector().detect(
        fixture(texture: false),
      );
      expect(r.hasDocument, isTrue);
      expect(r.blurScore, lessThan(1));
      expect(
        const QualityThresholds()
            .warningsFor(r)
            .any((w) => w.type == WarningType.blur),
        isTrue,
      );
    },
  );
  test('too dark, glare and incomplete paper produce warnings', () async {
    final d = PureDartDocumentDetector();
    const t = QualityThresholds();
    final dark = await d.detect(
      fixture(paper: 40, background: 0, texture: false),
    );
    expect(dark.hasDocument, isTrue);
    expect(
      t.warningsFor(dark).map((w) => w.type),
      contains(WarningType.tooDark),
    );
    final bright = await d.detect(fixture(paper: 255, texture: false));
    expect(
      t.warningsFor(bright).map((w) => w.type),
      contains(WarningType.tooBright),
    );
    final edge = await d.detect(
      fixture(
        quad: const [
          Offset(0, 30),
          Offset(210, 30),
          Offset(210, 180),
          Offset(0, 180),
        ],
      ),
    );
    expect(
      t.warningsFor(edge).map((w) => w.type),
      contains(WarningType.outOfFrame),
    );
  });
  test('disposal is enforced', () async {
    final d = PureDartDocumentDetector()..dispose();
    expect(() => d.detectSync(fixture()), throwsStateError);
  });
}
