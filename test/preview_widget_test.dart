import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'controller_test.dart' show FakeSource;

const corners = [
  Offset(.2, .2),
  Offset(.8, .2),
  Offset(.8, .8),
  Offset(.2, .8),
];

class _PreviewSource extends FakeSource {
  @override
  Size get previewSize => const Size(400, 300);
  @override
  Widget buildPreview() =>
      const ColoredBox(key: Key('native-preview'), color: Colors.black);
}

class _Canvas extends Fake implements Canvas {
  final paths = <Path>[];
  final colors = <int>[];
  @override
  void drawPath(Path path, Paint paint) {
    paths.add(Path.from(path));
    colors.add(paint.color.toARGB32());
  }
}

void expectPoints(List<Offset> actual, List<Offset> expected) {
  expect(actual.length, expected.length);
  for (var i = 0; i < actual.length; i++) {
    expect((actual[i] - expected[i]).distance, lessThan(1e-6));
  }
}

void main() {
  test(
    'contain/cover/fill project known corners with letterbox and crop offsets',
    () {
      const source = Size(400, 300), viewport = Size(800, 800);
      expectPoints(
        projectDocumentQuad(
          normalizedQuad: corners,
          imageSize: source,
          viewportSize: viewport,
        ),
        const [
          Offset(160, 220),
          Offset(640, 220),
          Offset(640, 580),
          Offset(160, 580),
        ],
      );
      expectPoints(
        projectDocumentQuad(
          normalizedQuad: corners,
          imageSize: source,
          viewportSize: viewport,
          fit: BoxFit.cover,
        ),
        const [
          Offset(80, 160),
          Offset(720, 160),
          Offset(720, 640),
          Offset(80, 640),
        ],
      );
      expectPoints(
        projectDocumentQuad(
          normalizedQuad: corners,
          imageSize: source,
          viewportSize: const Size(800, 400),
          fit: BoxFit.fill,
        ),
        const [
          Offset(160, 80),
          Offset(640, 80),
          Offset(640, 320),
          Offset(160, 320),
        ],
      );
      final aligned = projectDocumentQuad(
        normalizedQuad: corners,
        imageSize: source,
        viewportSize: viewport,
        fit: BoxFit.cover,
        alignment: Alignment.topLeft,
      );
      expect(aligned[0].dx, closeTo(640 / 3, 1e-6));
      expect(aligned[1].dx, greaterThan(800));
    },
  );
  test(
    'normalized analysis corners match 4K frame rendered at different logical DPI sizes',
    () {
      final report = QualityReport(
        result: DetectionResult(
          hasDocument: true,
          quad: const [
            Offset(128, 72),
            Offset(512, 72),
            Offset(512, 288),
            Offset(128, 288),
          ],
        ),
        frameSize: (width: 640, height: 360),
        capturedAt: DateTime.now(),
        sequence: 1,
        analysisTime: Duration.zero,
      );
      final value = DocumentPreviewStatus.fromReport(
        report,
        warnings: const [],
      );
      expectPoints(
        projectDocumentQuad(
          normalizedQuad: value.normalizedQuad!,
          imageSize: const Size(3840, 2160),
          viewportSize: const Size(1920, 1080),
        ),
        const [
          Offset(384, 216),
          Offset(1536, 216),
          Offset(1536, 864),
          Offset(384, 864),
        ],
      );
      expectPoints(
        projectDocumentQuad(
          normalizedQuad: value.normalizedQuad!,
          imageSize: const Size(3840, 2160),
          viewportSize: const Size(960, 540),
        ),
        const [
          Offset(192, 108),
          Offset(768, 108),
          Offset(768, 432),
          Offset(192, 432),
        ],
      );
    },
  );
  testWidgets('outline is closed and app colors follow quality changes', (
    tester,
  ) async {
    final source = _PreviewSource();
    final value = ValueNotifier(
      DocumentPreviewStatus(
        state: DocumentPreviewState.blurry,
        normalizedQuad: corners,
      ),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DocumentCameraPreview(
          frameSource: source,
          status: value,
          frameStyle: DocumentFrameStyle.outline,
          warningColor: Colors.purple,
          validColor: Colors.green,
        ),
      ),
    );
    final finder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is DocumentCornersPainter,
    );
    _Canvas paint() {
      final canvas = _Canvas();
      tester
          .widget<CustomPaint>(finder)
          .painter!
          .paint(canvas, tester.getSize(finder));
      return canvas;
    }

    final canvas = paint();
    expect(canvas.paths, hasLength(1));
    expect(canvas.paths.single.computeMetrics().single.isClosed, isTrue);
    expect(canvas.colors, [Colors.purple.toARGB32()]);
    value.value = DocumentPreviewStatus(
      state: DocumentPreviewState.clear,
      normalizedQuad: corners,
    );
    await tester.pump();
    expect(paint().colors, [Colors.green.toARGB32()]);
    await tester.pumpWidget(const SizedBox.shrink());
    value.dispose();
    await source.stream.close();
  });
  for (final fit in [BoxFit.contain, BoxFit.cover]) {
    testWidgets(
      'native preview and four painted corners share the $fit transform',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 800));
        final source = _PreviewSource();
        final value = ValueNotifier(
          DocumentPreviewStatus(
            state: DocumentPreviewState.clear,
            normalizedQuad: corners,
          ),
        );
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: DocumentCameraPreview(
              frameSource: source,
              status: value,
              fit: fit,
            ),
          ),
        );
        final rect = tester.getRect(find.byKey(const Key('native-preview')));
        if (fit == BoxFit.contain) {
          expect(rect, const Rect.fromLTWH(0, 100, 800, 600));
        } else {
          expect(rect.left, closeTo(-400 / 3, 1e-6));
          expect(rect.height, 800);
        }
        final finder = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is DocumentCornersPainter,
        );
        _Canvas paint() {
          final painter = tester.widget<CustomPaint>(finder).painter!;
          final canvas = _Canvas();
          painter.paint(canvas, tester.getSize(finder));
          return canvas;
        }

        final canvas = paint();
        expect(canvas.paths, hasLength(4));
        final expected = fit == BoxFit.contain
            ? const [
                Offset(160, 220),
                Offset(640, 220),
                Offset(640, 580),
                Offset(160, 580),
              ]
            : const [
                Offset(80, 160),
                Offset(720, 160),
                Offset(720, 640),
                Offset(80, 640),
              ];
        for (var i = 0; i < 4; i++) {
          final corner = canvas.paths[i]
              .computeMetrics()
              .single
              .getTangentForOffset(24)!
              .position;
          expect((corner - expected[i]).distance, lessThan(.001));
        }
        expect(canvas.colors, everyElement(0xff69f0ae));
        value.value = DocumentPreviewStatus(
          state: DocumentPreviewState.blurry,
          normalizedQuad: corners.map((p) => p + const Offset(.02, 0)).toList(),
        );
        await tester.pump();
        expect(paint().colors, everyElement(0xffffffff));
        value.value = DocumentPreviewStatus(
          state: DocumentPreviewState.noDocument,
        );
        await tester.pump();
        expect(paint().paths, isEmpty);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: DocumentCameraPreview(
              frameSource: source,
              status: value,
              fit: fit,
              showDocumentCorners: false,
            ),
          ),
        );
        expect(finder, findsNothing);
        expect(tester.getRect(find.byKey(const Key('native-preview'))), rect);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        value.dispose();
        await source.stream.close();
        await tester.binding.setSurfaceSize(null);
      },
    );
  }
}
