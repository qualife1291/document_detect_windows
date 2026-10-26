import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui';
import 'package:image/image.dart' as img;
import '../camera/frame_source.dart';
import '../detection/detector_facade.dart';
import '../detection/detection_result.dart';
import '../detection/geometry.dart';
import '../warnings/preview_warning.dart';
import 'captured_document.dart';
import 'capture_cancellation.dart';
import 'document_image_filter.dart';
import 'crop_geometry.dart';

class CropPipeline {
  const CropPipeline({
    this.jpegQuality = 90,
    this.analysisWidth = 640,
    this.maxOutputDimension,
    this.imageFilter = DocumentImageFilter.original,
    this.cropPadding = .02,
  });
  final int jpegQuality, analysisWidth;

  /// Limit the corrected crop during resampling, not after a full-size warp.
  /// Null preserves full-resolution output. Original JPEG always remains full size.
  final int? maxOutputDimension;
  final DocumentImageFilter imageFilter;

  /// Outward margin per edge, as a fraction of the shortest detected edge.
  /// Defaults to 2% to retain content near approximate low-resolution corners.
  /// Set 0 for an exact detected-quad crop; valid range is 0..0.1. The margin
  /// shrinks uniformly if the source frame has insufficient space.
  final double cropPadding;

  Future<CapturedDocument?> capture(
    FrameBuffer frame, {
    String? saveDirectory,
    QualityThresholds? requiredQuality,
    List<Offset>? expectedNormalizedQuad,
    double maximumMotion = .015,
    CaptureCancellation? cancellation,
    void Function(String event, Map<String, Object?> fields)? onDiagnostic,
  }) async {
    if (jpegQuality < 1 || jpegQuality > 100) {
      throw ArgumentError.value(jpegQuality, 'jpegQuality');
    }
    if (maxOutputDimension != null &&
        (maxOutputDimension! < 2 || maxOutputDimension! > 8192)) {
      throw ArgumentError.value(maxOutputDimension, 'maxOutputDimension');
    }
    if (!cropPadding.isFinite || cropPadding < 0 || cropPadding > .1) {
      throw ArgumentError.value(cropPadding, 'cropPadding', 'Expected 0..0.1');
    }
    if (cancellation?.isCancelled ?? false) return null;
    final transfer = TransferableTypedData.fromList([frame.rgba]);
    final width = frame.width,
        height = frame.height,
        sequence = frame.sequence,
        at = frame.capturedAt;
    final quality = jpegQuality, maxWidth = analysisWidth;
    final limit = maxOutputDimension, filter = imageFilter;
    final padding = cropPadding;
    final outcome = await runCaptureWorker<_CropOutcome>(() async {
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
      final timings = <String, int>{'detectionMs': watch.elapsedMilliseconds};
      final warnings =
          requiredQuality?.warningsFor(detection) ?? const <PreviewWarning>[];
      _CropOutcome rejected(String reason, {double? motion}) =>
          _CropOutcome(null, {
            'decision': reason,
            ..._detectionFields(detection, width, height),
            ...timings,
            'qualityWarnings': warnings.map((w) => w.type.name).toList(),
            if (motion != null) 'maxCornerMotion': motion,
            if (motion != null) 'maximumMotion': maximumMotion,
          });
      if (!detection.hasDocument) return rejected('no_document');
      if (warnings.isNotEmpty) return rejected('quality');
      if (expectedNormalizedQuad != null) {
        if (expectedNormalizedQuad.length != 4) {
          return rejected('invalid_expected_quad');
        }
        var motion = 0.0;
        for (var i = 0; i < 4; i++) {
          final p = detection.quad![i];
          motion = math.max(
            motion,
            (Offset(p.dx / width, p.dy / height) - expectedNormalizedQuad[i])
                .distance,
          );
        }
        if (motion > maximumMotion) return rejected('motion', motion: motion);
      }
      final source = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: full.rgba.buffer,
        bytesOffset: full.rgba.offsetInBytes,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      var stage = watch.elapsedMilliseconds;
      final geometry = CropGeometry.fromDetection(
        detection.quad!,
        width: width,
        height: height,
        padding: padding,
      );
      final cropped = warpPerspective(
        source,
        geometry.quad,
        maxOutputDimension: limit,
      );
      timings['warpMs'] = watch.elapsedMilliseconds - stage;
      stage = watch.elapsedMilliseconds;
      filterDocument(cropped, filter);
      timings['filterMs'] = watch.elapsedMilliseconds - stage;
      stage = watch.elapsedMilliseconds;
      final original = img.encodeJpg(source, quality: quality);
      timings['encodeOriginalMs'] = watch.elapsedMilliseconds - stage;
      stage = watch.elapsedMilliseconds;
      final encoded = img.encodeJpg(cropped, quality: quality);
      timings['encodeCropMs'] = watch.elapsedMilliseconds - stage;
      final captured = CapturedDocument(
        originalJpeg: original,
        croppedJpeg: encoded,
        quad: detection.quad!,
        cropQuad: geometry.quad,
        blurScore: detection.blurScore,
        coverageRatio: detection.coverageRatio,
        capturedAt: at,
        savedPath: null,
        processingTime: watch.elapsed,
      );
      return _CropOutcome(captured, {
        'decision': 'accepted',
        ..._detectionFields(detection, width, height),
        ...timings,
        'cropQuad': geometry.quad
            .map((p) => [p.dx / width, p.dy / height])
            .toList(),
        'cropPadding': padding,
        'paddingRequestedPx': geometry.requestedPaddingPixels,
        'paddingAppliedPx': geometry.appliedPaddingPixels,
        'paddingLimited': geometry.paddingLimited,
        'outputSize': [cropped.width, cropped.height],
        'filter': filter.name,
      });
    }, cancellation: cancellation);
    if (outcome != null && !(cancellation?.isCancelled ?? false)) {
      try {
        onDiagnostic?.call('capture_processing', outcome.fields);
      } catch (_) {
        /* Diagnostic sink is optional. */
      }
    }
    final captured = outcome?.captured;
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
      cropQuad: captured.cropQuad,
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
img.Image warpPerspective(
  img.Image source,
  List<Offset> q, {
  int? maxOutputDimension,
}) {
  if (maxOutputDimension != null &&
      (maxOutputDimension < 2 || maxOutputDimension > 8192)) {
    throw ArgumentError.value(maxOutputDimension, 'maxOutputDimension');
  }
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
  // Exact integer, axis-aligned corners describe inclusive source pixels.
  // Preserve them byte-for-byte instead of mapping N pixels to N-1 and blurring
  // high-frequency text. Never snap a fractional or perspective quadrilateral.
  final rect = _pixelCrop(q);
  if (rect != null && rect.width * rect.height > 33554432) {
    throw ArgumentError('Crop too large');
  }
  if (rect != null &&
      source.format == img.Format.uint8 &&
      !source.hasPalette &&
      source.numChannels >= 3 &&
      (maxOutputDimension == null ||
          math.max(rect.width, rect.height) <= maxOutputDimension)) {
    return img.copyCrop(
      source,
      x: rect.left.toInt(),
      y: rect.top.toInt(),
      width: rect.width.toInt(),
      height: rect.height.toInt(),
    );
  }
  var w = math.max(
    2,
    math.max((q[1] - q[0]).distance, (q[2] - q[3]).distance).round(),
  );
  var h = math.max(
    2,
    math.max((q[3] - q[0]).distance, (q[2] - q[1]).distance).round(),
  );
  if (maxOutputDimension != null && math.max(w, h) > maxOutputDimension) {
    final scale = maxOutputDimension / math.max(w, h);
    w = math.max(2, (w * scale).round());
    h = math.max(2, (h * scale).round());
  }
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
  final data = source.data;
  final fast =
      data is img.ImageDataUint8 &&
      !source.hasPalette &&
      source.numChannels >= 3;
  final input = fast ? data.data : null;
  final bytes = (output.data! as img.ImageDataUint8).data;
  final channels = source.numChannels, stride = source.rowStride;
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
      if (input != null) {
        final x0 = sx.toInt(), y0 = sy.toInt();
        final x1 = math.min(x0 + 1, source.width - 1),
            y1 = math.min(y0 + 1, source.height - 1);
        final fx = sx - x0, fy = sy - y0;
        final p00 = y0 * stride + x0 * channels,
            p10 = y0 * stride + x1 * channels;
        final p01 = y1 * stride + x0 * channels,
            p11 = y1 * stride + x1 * channels;
        final to = (y * w + x) * 3;
        for (var c = 0; c < 3; c++) {
          final top = input[p00 + c] + (input[p10 + c] - input[p00 + c]) * fx;
          final bottom =
              input[p01 + c] + (input[p11 + c] - input[p01 + c]) * fx;
          bytes[to + c] = (top + (bottom - top) * fy).round().clamp(0, 255);
        }
        continue;
      }
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

Rect? _pixelCrop(List<Offset> q) {
  if (q.any(
        (p) => p.dx != p.dx.roundToDouble() || p.dy != p.dy.roundToDouble(),
      ) ||
      q[0].dy != q[1].dy ||
      q[1].dx != q[2].dx ||
      q[2].dy != q[3].dy ||
      q[3].dx != q[0].dx) {
    return null;
  }
  return Rect.fromLTWH(
    q[0].dx,
    q[0].dy,
    q[1].dx - q[0].dx + 1,
    q[3].dy - q[0].dy + 1,
  );
}

class _CropOutcome {
  const _CropOutcome(this.captured, this.fields);
  final CapturedDocument? captured;
  final Map<String, Object?> fields;
}

Map<String, Object?> _detectionFields(
  DetectionResult result,
  int width,
  int height,
) => {
  'hasDocument': result.hasDocument,
  'blur': result.blurScore.round(),
  'brightness': result.brightnessScore,
  'coverage': result.coverageRatio,
  'margin': result.edgeMargin,
  'tiltDeg': result.tiltAngle,
  'quad': result.quad?.map((p) => [p.dx / width, p.dy / height]).toList(),
};
