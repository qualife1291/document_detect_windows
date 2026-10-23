import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'package:windows_doc_capture/src/capture/document_image_filter.dart';
import 'fixtures.dart';

void main() {
  test('complete document wins over a large clipped background', () async {
    final frame = fixture(width: 640, height: 480, background: 95, paper: 150);
    // A bright desk strip touches three sensor borders and dominates Otsu.
    for (var y = 0; y < 60; y++) {
      for (var x = 0; x < frame.width; x++) {
        final i = (y * frame.width + x) * 4;
        frame.rgba[i] = frame.rgba[i + 1] = frame.rgba[i + 2] = 240;
      }
    }
    final result = await PureDartDocumentDetector().detect(frame);
    expect(result.hasDocument, isTrue);
    expect(result.edgeMargin, greaterThan(.12));
    for (var i = 0; i < 4; i++) {
      expect(
        (result.quad![i] -
                [
                  const Offset(115, 86),
                  const Offset(525, 86),
                  const Offset(525, 394),
                  const Offset(115, 394),
                ][i])
            .distance,
        lessThan(12),
      );
    }
  });
  test(
    'low contrast with distracting high contrast scene edge is detected',
    () async {
      final frame = fixture(
        width: 640,
        height: 480,
        background: 110,
        paper: 133,
      );
      for (var y = 0; y < 45; y++) {
        for (var x = 0; x < frame.width; x++) {
          final i = (y * frame.width + x) * 4;
          frame.rgba[i] = frame.rgba[i + 1] = frame.rgba[i + 2] = 250;
        }
      }
      final result = await PureDartDocumentDetector().detect(frame);
      expect(result.hasDocument, isTrue);
      expect(result.coverageRatio, closeTo(.4096, .04));
      expect(result.edgeMargin, greaterThan(.12));
    },
  );
  test(
    'blank and unstructured low-level noise never acquire a document',
    () async {
      final frame = fixture(document: false, background: 110);
      for (var i = 0; i < frame.rgba.length; i += 4) {
        final value = 108 + ((i * 31 + i ~/ 17) % 5);
        frame.rgba[i] = frame.rgba[i + 1] = frame.rgba[i + 2] = value;
      }
      expect(
        (await PureDartDocumentDetector().detect(frame)).hasDocument,
        isFalse,
      );
    },
  );
  test('fast warp agrees with library bilinear sampling for RGB and RGBA', () {
    for (final channels in [3, 4]) {
      final source = img.Image(width: 37, height: 29, numChannels: channels);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgba(
            x,
            y,
            x * 7 % 256,
            y * 11 % 256,
            (x + y) * 9 % 256,
            128,
          );
        }
      }
      const q = [Offset(2, 3), Offset(33, 3), Offset(33, 25), Offset(2, 25)];
      final output = warpPerspective(source, q);
      for (var y = 0; y < output.height; y++) {
        for (var x = 0; x < output.width; x++) {
          final reference = source.getPixelInterpolate(
            2 + 31 * x / (output.width - 1),
            3 + 22 * y / (output.height - 1),
            interpolation: img.Interpolation.linear,
          );
          final actual = output.getPixel(x, y);
          expect(actual.r, closeTo(reference.r, 1));
          expect(actual.g, closeTo(reference.g, 1));
          expect(actual.b, closeTo(reference.b, 1));
        }
      }
    }
  });
  test(
    'warp limits output before sampling and supports single-channel fallback',
    () {
      final source = img.Image(width: 400, height: 300, numChannels: 1);
      source.clear(img.ColorUint8.rgb(120, 120, 120));
      final output = warpPerspective(source, const [
        Offset(0, 0),
        Offset(399, 0),
        Offset(399, 299),
        Offset(0, 299),
      ], maxOutputDimension: 100);
      expect(output.width, 100);
      expect(output.height, 75);
      expect(output.getPixel(50, 50).r, 120);
      expect(
        () => warpPerspective(source, const [], maxOutputDimension: 1),
        throwsArgumentError,
      );
    },
  );
  test(
    'original preserves color, grayscale is explicit, blank enhancement is safe',
    () {
      final image = img.Image(width: 10, height: 10);
      image.clear(img.ColorUint8.rgb(80, 120, 160));
      final before = Uint8List.fromList(
        (image.data! as img.ImageDataUint8).data,
      );
      filterDocument(image, DocumentImageFilter.original);
      expect((image.data! as img.ImageDataUint8).data, orderedEquals(before));
      filterDocument(image, DocumentImageFilter.enhance);
      expect((image.data! as img.ImageDataUint8).data, orderedEquals(before));
      filterDocument(image, DocumentImageFilter.grayscale);
      final pixel = image.getPixel(5, 5);
      expect(pixel.r, pixel.g);
      expect(pixel.g, pixel.b);
      expect(pixel.r, inInclusiveRange(110, 115));
    },
  );
  test('enhance expands printed contrast and caps gain', () {
    final image = img.Image(width: 10, height: 10);
    for (var y = 0; y < 10; y++) {
      for (var x = 0; x < 10; x++) {
        final v = x < 5 ? 80 : 180;
        image.setPixelRgb(x, y, v, v, v);
      }
    }
    filterDocument(image, DocumentImageFilter.enhance);
    expect(image.getPixel(0, 0).r, 0);
    expect(image.getPixel(9, 9).r, 150);
  });
  test('UI diagnostic callback is never sent to the capture worker', () async {
    final port = ReceivePort();
    try {
      var logged = false;
      final result = await const CropPipeline().capture(
        fixture(),
        onDiagnostic: (_, __) {
          port.sendPort.send('local');
          logged = true;
        },
      );
      expect(result, isNotNull);
      expect(logged, isTrue);
    } finally {
      port.close();
    }
  });
  test(
    'capture diagnostic identifies rejection and accepted processing stages',
    () async {
      final fields = <Map<String, Object?>>[];
      void log(String event, Map<String, Object?> data) {
        expect(event, 'capture_processing');
        fields.add(data);
      }

      final pipeline = const CropPipeline(
        maxOutputDimension: 100,
        imageFilter: DocumentImageFilter.grayscale,
      );
      expect(
        await pipeline.capture(fixture(document: false), onDiagnostic: log),
        isNull,
      );
      expect(fields.last['decision'], 'no_document');
      expect(
        await pipeline.capture(
          fixture(texture: false),
          requiredQuality: const QualityThresholds(),
          onDiagnostic: log,
        ),
        isNull,
      );
      expect(fields.last['decision'], 'quality');
      expect(fields.last['qualityWarnings'], contains('blur'));
      expect(
        await pipeline.capture(
          fixture(),
          expectedNormalizedQuad: normalized
              .map((p) => p + const Offset(.2, 0))
              .toList(),
          onDiagnostic: log,
        ),
        isNull,
      );
      expect(fields.last['decision'], 'motion');
      expect(fields.last['maxCornerMotion'], greaterThan(.015));
      final result = await pipeline.capture(fixture(), onDiagnostic: log);
      expect(result, isNotNull);
      final crop = img.decodeJpg(result!.croppedJpeg)!;
      expect(crop.width, 100);
      expect(img.decodeJpg(result.originalJpeg)!.width, 320);
      expect(fields.last['decision'], 'accepted');
      expect(fields.last['filter'], 'grayscale');
      for (final stage in [
        'detectionMs',
        'warpMs',
        'filterMs',
        'encodeOriginalMs',
        'encodeCropMs',
      ]) {
        expect(fields.last[stage], isNonNegative);
      }
      expect(
        await pipeline.capture(
          fixture(),
          onDiagnostic: (_, __) => throw StateError('sink'),
        ),
        isNotNull,
      );
    },
  );
}
