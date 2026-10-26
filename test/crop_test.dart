import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'fixtures.dart';

void main() {
  test(
    'default capture returns JPEGs without accessing capture files or directories',
    () async {
      var fileAccesses = 0;
      final result = await IOOverrides.runZoned(
        () => const CropPipeline().capture(fixture()),
        createFile: (_) {
          fileAccesses++;
          throw StateError('Unexpected file IO');
        },
        createDirectory: (_) {
          fileAccesses++;
          throw StateError('Unexpected directory IO');
        },
        getSystemTempDirectory: () {
          fileAccesses++;
          throw StateError('Unexpected temp directory');
        },
      );
      expect(result, isNotNull);
      expect(result!.savedPath, isNull);
      expect(img.decodeJpg(result.originalJpeg), isNotNull);
      expect(img.decodeJpg(result.croppedJpeg), isNotNull);
      expect(fileAccesses, 0);
    },
  );
  test('exact rectangular crop preserves fine print and all edge pixels', () {
    final source = img.Image(width: 40, height: 30, numChannels: 4);
    for (var y = 0; y < 30; y++) {
      for (var x = 0; x < 40; x++) {
        source.setPixelRgba(x, y, x.isEven ? 255 : 0, y * 7, x + y, 255);
      }
    }
    final crop = warpPerspective(source, const [
      Offset(4, 3),
      Offset(35, 3),
      Offset(35, 26),
      Offset(4, 26),
    ]);
    expect(crop.width, 32);
    expect(crop.height, 24);
    for (var y = 0; y < crop.height; y++) {
      for (var x = 0; x < crop.width; x++) {
        final a = crop.getPixel(x, y), b = source.getPixel(x + 4, y + 3);
        expect([a.r, a.g, a.b], [b.r, b.g, b.b]);
      }
    }
    final limited = warpPerspective(source, const [
      Offset(4, 3),
      Offset(35, 3),
      Offset(35, 26),
      Offset(4, 26),
    ], maxOutputDimension: 20);
    expect(limited.width, 20);
    final fractional = warpPerspective(source, const [
      Offset(4.5, 3),
      Offset(35.5, 3),
      Offset(35.5, 26),
      Offset(4.5, 26),
    ]);
    expect(fractional.getPixel(0, 0).r, inInclusiveRange(127, 128));
    expect(source.width, 40);
  });
  test('perspective inverse mapping preserves all four colored corners', () {
    final source = img.Image(width: 100, height: 80);
    for (var y = 0; y < 80; y++) {
      for (var x = 0; x < 100; x++) {
        source.setPixelRgb(x, y, x * 2, y * 3, 50);
      }
    }
    const q = [Offset(10, 10), Offset(90, 20), Offset(80, 70), Offset(20, 60)];
    final crop = warpPerspective(source, q);
    for (final item in [
      (0, 0, q[0]),
      (crop.width - 1, 0, q[1]),
      (crop.width - 1, crop.height - 1, q[2]),
      (0, crop.height - 1, q[3]),
    ]) {
      final p = crop.getPixel(item.$1, item.$2);
      expect(p.r, closeTo(item.$3.dx * 2, 2));
      expect(p.g, closeTo(item.$3.dy * 3, 2));
    }
    expect(
      () => warpPerspective(source, const [
        Offset.zero,
        Offset.zero,
        Offset.zero,
        Offset.zero,
      ]),
      throwsArgumentError,
    );
  });
  test(
    'fresh full resolution crop encodes JPEG and saves exact bytes to unique files',
    () async {
      final dir = await Directory.systemTemp.createTemp('doc-capture-test-');
      try {
        final frame = fixture(width: 1280, height: 960);
        final a = (await const CropPipeline().capture(
          frame,
          saveDirectory: dir.path,
        ))!;
        final b = (await const CropPipeline().capture(
          frame,
          saveDirectory: dir.path,
        ))!;
        expect(img.decodeJpg(a.originalJpeg)!.width, 1280);
        final cropped = img.decodeJpg(a.croppedJpeg)!;
        expect(cropped.width, closeTo(1280 * .64 + 2 * .02 * 960 * .64, 8));
        expect(cropped.height, closeTo(960 * .64 * 1.04, 8));
        expect(a.quad.first.dx, closeTo(1280 * .18, 8));
        expect(a.savedPath, isNot(b.savedPath));
        expect(a.cropQuad.first.dx, lessThan(a.quad.first.dx));
        expect(a.cropQuad.last.dy, greaterThan(a.quad.last.dy));
        expect(
          await File(a.savedPath!).readAsBytes(),
          orderedEquals(a.croppedJpeg),
        );
        expect(a.capturedAt, frame.capturedAt);
        expect(a.processingTime, greaterThan(Duration.zero));
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'no document and automatic poor quality never produce an output',
    () async {
      expect(
        await const CropPipeline().capture(fixture(document: false)),
        isNull,
      );
      expect(
        await const CropPipeline().capture(
          fixture(texture: false),
          requiredQuality: const QualityThresholds(),
        ),
        isNull,
      );
    },
  );
  test(
    'file IO failures propagate instead of returning a nonexistent savedPath',
    () async {
      final dir = await Directory.systemTemp.createTemp('doc-capture-io-');
      try {
        final file = await File('${dir.path}/file').writeAsString('occupied');
        await expectLater(
          const CropPipeline().capture(fixture(), saveDirectory: file.path),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'moving full-resolution snapshot is rejected against the stable quad',
    () async {
      final frame = fixture();
      final detected = await PureDartDocumentDetector().detect(frame);
      final expected = detected.quad!
          .map((p) => Offset(p.dx / frame.width + .08, p.dy / frame.height))
          .toList();
      expect(
        await const CropPipeline().capture(
          frame,
          expectedNormalizedQuad: expected,
        ),
        isNull,
      );
      final same = detected.quad!
          .map((p) => Offset(p.dx / frame.width, p.dy / frame.height))
          .toList();
      expect(
        await const CropPipeline().capture(frame, expectedNormalizedQuad: same),
        isNotNull,
      );
    },
  );
}
