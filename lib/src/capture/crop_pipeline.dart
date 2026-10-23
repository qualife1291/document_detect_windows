import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui';
import 'package:image/image.dart' as img;
import '../camera/frame_source.dart';
import '../detection/detector_facade.dart';
import '../detection/geometry.dart';
import '../warnings/preview_warning.dart';
import 'captured_document.dart';
import 'capture_cancellation.dart';

class CropPipeline {
  const CropPipeline({this.jpegQuality = 90, this.analysisWidth = 640});
  final int jpegQuality, analysisWidth;

  Future<CapturedDocument?> capture(
    FrameBuffer frame, {
    String? saveDirectory,
    QualityThresholds? requiredQuality,
    List<Offset>? expectedNormalizedQuad,
    double maximumMotion = .015,
    CaptureCancellation? cancellation,
  }) async {
    if (jpegQuality < 1 || jpegQuality > 100) {
      throw ArgumentError.value(jpegQuality, 'jpegQuality');
    }
    if (cancellation?.isCancelled ?? false) return null;
    final transfer = TransferableTypedData.fromList([frame.rgba]);
    final width = frame.width,
        height = frame.height,
        sequence = frame.sequence,
        at = frame.capturedAt;
    final quality = jpegQuality, maxWidth = analysisWidth;
    final captured = await runCaptureWorker<CapturedDocument?>(() async {
      final watch = Stopwatch()..start();
      final full = FrameBuffer(
        width: width,
        height: height,
        rgba: transfer.materialize().asUint8List(),
        capturedAt: at,
        sequence: sequence,
      );
      final detector = createDocumentDetector(maxWidth: maxWidth);
      // Re-detect the snapshot itself: never warp new pixels with stale corners.
      final detection = await detector.detect(full);
      detector.dispose();
      if (!detection.hasDocument ||
          (requiredQuality != null &&
              requiredQuality.warningsFor(detection).isNotEmpty)) {
        return null;
      }
      if (expectedNormalizedQuad != null) {
        if (expectedNormalizedQuad.length != 4) return null;
        for (var i = 0; i < 4; i++) {
          final p = detection.quad![i];
          if ((Offset(p.dx / width, p.dy / height) - expectedNormalizedQuad[i])
                  .distance >
              maximumMotion) {
            return null;
          }
        }
      }
      final source = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: full.rgba.buffer,
        bytesOffset: full.rgba.offsetInBytes,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      final cropped = warpPerspective(source, detection.quad!);
      final original = img.encodeJpg(source, quality: quality);
      final encoded = img.encodeJpg(cropped, quality: quality);
      return CapturedDocument(
        originalJpeg: original,
        croppedJpeg: encoded,
        quad: detection.quad!,
        blurScore: detection.blurScore,
        coverageRatio: detection.coverageRatio,
        capturedAt: at,
        savedPath: null,
        processingTime: watch.elapsed,
      );
    }, cancellation: cancellation);
    if (captured == null || (cancellation?.isCancelled ?? false)) return null;
    if (saveDirectory == null) return captured;
    final saveClock = Stopwatch()..start();
    final directory = await Directory(saveDirectory).create(recursive: true);
    if (cancellation?.isCancelled ?? false) return null;
    final random = math.Random.secure();
    final name = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final file = File('${directory.path}${Platform.pathSeparator}$name.part');
    final finalPath = '${directory.path}${Platform.pathSeparator}$name.jpg';
    await file.create(exclusive: true);
    try {
      await file.writeAsBytes(captured.croppedJpeg, flush: true);
      if (cancellation?.isCancelled ?? false) {
        await file.delete();
        return null;
      }
      await file.rename(finalPath);
      if (cancellation?.isCancelled ?? false) {
        await File(finalPath).delete();
        return null;
      }
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
    return CapturedDocument(
      originalJpeg: captured.originalJpeg,
      croppedJpeg: captured.croppedJpeg,
      quad: captured.quad,
      blurScore: captured.blurScore,
      coverageRatio: captured.coverageRatio,
      capturedAt: captured.capturedAt,
      savedPath: finalPath,
      processingTime: captured.processingTime + saveClock.elapsed,
    );
  }
}

/// Inverse projective homography (unit rectangle -> quadrilateral), bilinear
/// sampling. Output dimensions follow opposing-edge lengths in source pixels.
img.Image warpPerspective(img.Image source, List<Offset> q) {
  if (q.length != 4 ||
      q.any(
        (p) =>
            !p.dx.isFinite ||
            !p.dy.isFinite ||
            p.dx < 0 ||
            p.dy < 0 ||
            p.dx > source.width - 1 ||
            p.dy > source.height - 1,
      ) ||
      polygonArea(q) < 1 ||
      List.generate(
        4,
        (i) => cross(q[i], q[(i + 1) % 4], q[(i + 2) % 4]),
      ).any((v) => v <= 0)) {
    throw ArgumentError('Expected a convex clockwise in-frame quadrilateral');
  }
  final w = math.max(
    2,
    math.max((q[1] - q[0]).distance, (q[2] - q[3]).distance).round(),
  );
  final h = math.max(
    2,
    math.max((q[3] - q[0]).distance, (q[2] - q[1]).distance).round(),
  );
  if (w * h > 33554432) throw ArgumentError('Crop too large');
  final dx1 = q[1].dx - q[2].dx, dx2 = q[3].dx - q[2].dx;
  final dy1 = q[1].dy - q[2].dy, dy2 = q[3].dy - q[2].dy;
  final dx3 = q[0].dx - q[1].dx + q[2].dx - q[3].dx;
  final dy3 = q[0].dy - q[1].dy + q[2].dy - q[3].dy;
  final det = dx1 * dy2 - dx2 * dy1;
  double g = 0, k = 0;
  if (dx3.abs() + dy3.abs() > 1e-8) {
    if (det.abs() < 1e-8) throw ArgumentError('Singular perspective');
    g = (dx3 * dy2 - dx2 * dy3) / det;
    k = (dx1 * dy3 - dx3 * dy1) / det;
  }
  final a = q[1].dx - q[0].dx + g * q[1].dx,
      b = q[3].dx - q[0].dx + k * q[3].dx;
  final d = q[1].dy - q[0].dy + g * q[1].dy,
      e = q[3].dy - q[0].dy + k * q[3].dy;
  final output = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    final v = y / (h - 1);
    for (var x = 0; x < w; x++) {
      final u = x / (w - 1), den = g * u + k * v + 1;
      final sx = ((a * u + b * v + q[0].dx) / den)
          .clamp(0, source.width - 1)
          .toDouble();
      final sy = ((d * u + e * v + q[0].dy) / den)
          .clamp(0, source.height - 1)
          .toDouble();
      final pixel = source.getPixelInterpolate(
        sx,
        sy,
        interpolation: img.Interpolation.linear,
      );
      output.setPixelRgb(x, y, pixel.r, pixel.g, pixel.b);
    }
  }
  return output;
}
