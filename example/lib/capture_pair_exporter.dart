import 'dart:io';
import 'package:file_selector_windows/file_selector_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';

/// Explicit example-only export. No decoding, re-encoding or camera operations.
class CapturePairExporter {
  const CapturePairExporter();

  Future<String?> chooseDirectory({String? initialDirectory}) =>
      FileSelectorWindows().getDirectoryPath(
        initialDirectory: initialDirectory,
        confirmButtonText: 'Xuất vào thư mục này',
      );

  /// Stage both files in a unique directory beside the final directory. Publish
  /// only after both writes close/flush; cancellation cleans only this staging
  /// directory. Once published, the requested export remains even after unmount.
  Future<Directory?> writePair(
    CapturedDocument document,
    Directory parent, {
    required bool Function() isCancelled,
  }) async {
    if (isCancelled()) return null;
    Directory? staging;
    Object? failure;
    try {
      final stamp = document.capturedAt.toUtc().microsecondsSinceEpoch;
      staging = await parent.createTemp('.capture-$stamp-');
      if (isCancelled()) return null;
      await writeBytes(
        File.fromUri(staging.uri.resolve('original.jpg')),
        document.originalJpeg,
      );
      if (isCancelled()) return null;
      await writeBytes(
        File.fromUri(staging.uri.resolve('cropped.jpg')),
        document.croppedJpeg,
      );
      if (isCancelled()) return null;
      final name = staging.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final destination = Directory.fromUri(
        parent.uri.resolve(name.substring(1)),
      );
      if (await FileSystemEntity.type(destination.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException('Export destination already exists');
      }
      if (isCancelled()) return null;
      final exported = await staging.rename(destination.path);
      staging = null;
      return exported;
    } catch (error) {
      failure = error;
      rethrow;
    } finally {
      if (staging != null) {
        try {
          if (await staging.exists()) await staging.delete(recursive: true);
        } catch (_) {
          // Keep the original IO failure. If cleanup itself is the only error,
          // surface it rather than reporting cancellation/success incorrectly.
          if (failure == null) rethrow;
        }
      }
    }
  }

  @protected
  Future<void> writeBytes(File file, Uint8List bytes) async {
    await file.create(exclusive: true);
    await file.writeAsBytes(bytes, flush: true);
  }
}
