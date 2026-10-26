import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'package:windows_doc_capture_example/capture_pair_exporter.dart';

CapturedDocument document() => CapturedDocument(
  originalJpeg: Uint8List.fromList([255, 216, 21, 34, 255, 217]),
  croppedJpeg: Uint8List.fromList([255, 216, 56, 78, 255, 217]),
  quad: const [],
  blurScore: 100,
  coverageRatio: .3,
  capturedAt: DateTime.utc(2026, 10, 26),
);

class _InterruptedExporter extends CapturePairExporter {
  _InterruptedExporter({this.fail = false, this.cancelAfter = 1});
  final bool fail;
  final int cancelAfter;
  bool cancelled = false;
  int writes = 0;
  @override
  Future<void> writeBytes(File file, Uint8List bytes) async {
    await super.writeBytes(file, bytes);
    writes++;
    if (fail && writes == 2) {
      throw const FileSystemException('Synthetic IO error');
    }
    if (!fail) cancelled = writes >= cancelAfter;
  }
}

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('pair-test-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'exports unchanged bytes from one capture without overwriting prior pairs',
    () async {
      final capture = document();
      final output = await Directory.fromUri(
        root.uri.resolve('Thư mục kiểm tra ảnh/'),
      ).create();
      final unrelated = File.fromUri(output.uri.resolve('existing.jpg'));
      await unrelated.writeAsBytes([1, 2, 3]);
      const exporter = CapturePairExporter();
      final first = (await exporter.writePair(
        capture,
        output,
        isCancelled: () => false,
      ))!;
      final second = (await exporter.writePair(
        capture,
        output,
        isCancelled: () => false,
      ))!;
      expect(first.path, isNot(second.path));
      for (final pair in [first, second]) {
        final entries = await pair.list().toList();
        expect(entries.map((f) => f.uri.pathSegments.last).toSet(), {
          'original.jpg',
          'cropped.jpg',
        });
        expect(
          await File.fromUri(pair.uri.resolve('original.jpg')).readAsBytes(),
          capture.originalJpeg,
        );
        expect(
          await File.fromUri(pair.uri.resolve('cropped.jpg')).readAsBytes(),
          capture.croppedJpeg,
        );
      }
      expect(await unrelated.readAsBytes(), [1, 2, 3]);
      expect((await output.list().toList()).length, 3);
    },
  );

  test('cancelled before writing creates no directory or files', () async {
    expect(
      await const CapturePairExporter().writePair(
        document(),
        root,
        isCancelled: () => true,
      ),
      isNull,
    );
    expect(await root.list().toList(), isEmpty);
  });

  test(
    'unmount cancellation between writes removes only its staged data',
    () async {
      final unrelated = File.fromUri(root.uri.resolve('keep.jpg'));
      await unrelated.writeAsString('keep');
      for (final count in [1, 2]) {
        final exporter = _InterruptedExporter(cancelAfter: count);
        expect(
          await exporter.writePair(
            document(),
            root,
            isCancelled: () => exporter.cancelled,
          ),
          isNull,
        );
        expect(exporter.writes, count);
        expect((await root.list().toList()).map((f) => f.path), [
          unrelated.path,
        ]);
      }
      expect(await unrelated.readAsString(), 'keep');
    },
  );

  test(
    'partial second-write failure publishes no pair and preserves caller files',
    () async {
      final keep = await root.createTemp('existing-pair-');
      final file = File.fromUri(keep.uri.resolve('original.jpg'));
      await file.writeAsString('existing');
      final exporter = _InterruptedExporter(fail: true);
      await expectLater(
        exporter.writePair(document(), root, isCancelled: () => false),
        throwsA(isA<FileSystemException>()),
      );
      expect(exporter.writes, 2);
      expect((await root.list().toList()).map((f) => f.path), [keep.path]);
      expect(await file.readAsString(), 'existing');
    },
  );

  test(
    'unavailable destination surfaces IO error without creating fallback files',
    () async {
      await expectLater(
        const CapturePairExporter().writePair(
          document(),
          Directory.fromUri(root.uri.resolve('missing/')),
          isCancelled: () => false,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await root.list().toList(), isEmpty);
    },
  );
}
