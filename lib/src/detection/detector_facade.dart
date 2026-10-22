import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import '../camera/frame_source.dart';
import 'document_detector.dart';
import 'detection_result.dart';
import 'geometry.dart';

/// SDK-floor-compatible fallback. No dartcv4 dependency is resolved by default.
DocumentDetector createDocumentDetector({int maxWidth = 640}) =>
    PureDartDocumentDetector(maxWidth: maxWidth);

/// Gaussian + Canny contours with an Otsu intensity-contour fallback.
/// Suited to a contrasting kiosk background; not a semantic document classifier.
class PureDartDocumentDetector implements DocumentDetector {
  PureDartDocumentDetector({this.maxWidth = 640}) {
    if (maxWidth < 32 || maxWidth > 1920) {
      throw ArgumentError.value(maxWidth, 'maxWidth');
    }
  }
  final int maxWidth;
  bool _disposed = false;
  @override
  Future<DetectionResult> detect(FrameBuffer frame) async => detectSync(frame);

  DetectionResult detectSync(FrameBuffer frame) {
    if (_disposed) throw StateError('Detector disposed');
    final w = math.min(frame.width, maxWidth);
    final h = math.max(2, (frame.height * w / frame.width).round());
    final gray = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final sy = math.min(frame.height - 1, (y * frame.height / h).floor());
      for (var x = 0; x < w; x++) {
        final sx = math.min(frame.width - 1, (x * frame.width / w).floor());
        final i = (sy * frame.width + sx) * 4;
        gray[y * w + x] =
            ((77 * frame.rgba[i] +
                150 * frame.rgba[i + 1] +
                29 * frame.rgba[i + 2]) >>
            8);
      }
    }
    final smooth = _gaussian(gray, w, h);
    var lo = 255, hi = 0;
    final hist = List<int>.filled(256, 0);
    for (final v in smooth) {
      hist[v]++;
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    if (hi - lo < 25) return DetectionResult.empty();
    final threshold = _otsu(hist, w * h);
    List<Offset>? best;
    double bestScore = 0;
    final canny = _canny(smooth, w, h);
    // Closed Canny contours plus both intensity polarities. Intensity fallback
    // handles an edge cut off by the sensor boundary (outOfFrame warning).
    for (var mode = 0; mode < 3; mode++) {
      bool foreground(int p) =>
          mode == 0 ? canny[p] != 0 : (smooth[p] > threshold) == (mode == 1);
      final visited = Uint8List(w * h);
      final queue = Int32List(w * h);
      for (var seed = 0; seed < smooth.length; seed++) {
        if (visited[seed] != 0 || !foreground(seed)) {
          continue;
        }
        var head = 0, tail = 1;
        queue[0] = seed;
        visited[seed] = 1;
        final boundary = <Offset>[];
        while (head < tail) {
          final p = queue[head++], x = p % w, y = p ~/ w;
          var border = false;
          for (final n in [
            x > 0 ? p - 1 : -1,
            x < w - 1 ? p + 1 : -1,
            y > 0 ? p - w : -1,
            y < h - 1 ? p + w : -1,
            if (mode == 0) ...[
              x > 0 && y > 0 ? p - w - 1 : -1,
              x < w - 1 && y > 0 ? p - w + 1 : -1,
              x > 0 && y < h - 1 ? p + w - 1 : -1,
              x < w - 1 && y < h - 1 ? p + w + 1 : -1,
            ],
          ]) {
            if (n < 0 || !foreground(n)) {
              border = true;
              continue;
            }
            if (visited[n] == 0) {
              visited[n] = 1;
              queue[tail++] = n;
            }
          }
          if (border) boundary.add(Offset(x.toDouble(), y.toDouble()));
        }
        if ((mode != 0 && tail < w * h * .05) || boundary.length < 20) continue;
        final quad = fitQuad(convexHull(boundary));
        if (quad == null) continue;
        final area = polygonArea(quad);
        if (area < w * h * .05 ||
            area > w * h * .97 ||
            (mode != 0 && tail / area < .75)) {
          continue;
        }
        final a =
            ((quad[1] - quad[0]).distance + (quad[2] - quad[3]).distance) / 2;
        final b =
            ((quad[3] - quad[0]).distance + (quad[2] - quad[1]).distance) / 2;
        final ratio = math.max(a, b) / math.min(a, b);
        if (ratio < 1.15 || ratio > 2.05 || tiltOf(quad) > 45) continue;
        // A background enclosing a dark document has low contour fill and/or
        // occupies the complete border; do not mistake it for the document.
        final score = area * (mode == 0 ? 1 : (tail / area).clamp(0, 1));
        if (score > bestScore) {
          best = quad;
          bestScore = score;
        }
      }
    }
    if (best == null) return DetectionResult.empty();
    double sum = 0, lapSum = 0, lapSquares = 0;
    var count = 0, clipped = 0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        // Exclude the paper/background edge from the sharpness score.
        if (!insideQuad(x - 4.0, y - 4.0, best) ||
            !insideQuad(x + 4.0, y + 4.0, best) ||
            !insideQuad(x - 4.0, y + 4.0, best) ||
            !insideQuad(x + 4.0, y - 4.0, best)) {
          continue;
        }
        final i = y * w + x, v = gray[i];
        sum += v;
        count++;
        if (v >= 250) clipped++;
        final lap =
            gray[i - 1] + gray[i + 1] + gray[i - w] + gray[i + w] - 4 * v;
        lapSum += lap;
        lapSquares += lap * lap;
      }
    }
    if (count == 0) return DetectionResult.empty();
    final a = (best[1] - best[0]).distance, b = (best[3] - best[0]).distance;
    final ratio = math.max(a, b) / math.min(a, b);
    var margin = 1.0;
    for (final p in best) {
      margin = math.min(
        margin,
        math.min(
          math.min(p.dx / w, (w - 1 - p.dx) / w),
          math.min(p.dy / h, (h - 1 - p.dy) / h),
        ),
      );
    }
    return DetectionResult(
      hasDocument: true,
      quad: best
          .map((p) => Offset(p.dx * frame.width / w, p.dy * frame.height / h))
          .toList(),
      coverageRatio: polygonArea(best) / (w * h),
      tiltAngle: tiltOf(best),
      edgeMargin: margin,
      blurScore: math.max(0, lapSquares / count - math.pow(lapSum / count, 2)),
      brightnessScore: sum / count / 255,
      clippingRatio: clipped / count,
      kind: (ratio - 1.414).abs() < .12
          ? DocumentKind.a4
          : (ratio - 1.586).abs() < .12
          ? DocumentKind.idCard
          : DocumentKind.unknown,
    );
  }

  @override
  void dispose() {
    _disposed = true;
  }
}

Uint8List _gaussian(Uint8List input, int w, int h) {
  const k = [1, 4, 6, 4, 1];
  final temp = Uint16List(w * h), out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var sum = 0;
      for (var i = -2; i <= 2; i++) {
        sum += input[y * w + (x + i).clamp(0, w - 1)] * k[i + 2];
      }
      temp[y * w + x] = sum;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var sum = 0;
      for (var i = -2; i <= 2; i++) {
        sum += temp[(y + i).clamp(0, h - 1) * w + x] * k[i + 2];
      }
      out[y * w + x] = sum >> 8;
    }
  }
  return out;
}

int _otsu(List<int> hist, int total) {
  double sum = 0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var count = 0, threshold = 0;
  double before = 0, best = -1;
  for (var i = 0; i < 255; i++) {
    count += hist[i];
    before += i * hist[i];
    if (count == 0 || count == total) continue;
    final diff = before / count - (sum - before) / (total - count);
    final score = count * (total - count) * diff * diff;
    if (score > best) {
      best = score;
      threshold = i;
    }
  }
  return threshold;
}

// Sobel gradients, direction-aware non-maximum suppression, double threshold,
// and 8-connected hysteresis on the Gaussian-smoothed image.
Uint8List _canny(Uint8List gray, int w, int h) {
  final magnitude = Uint16List(w * h), direction = Uint8List(w * h);
  var maximum = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final p = y * w + x;
      final gx =
          -gray[p - w - 1] +
          gray[p - w + 1] -
          2 * gray[p - 1] +
          2 * gray[p + 1] -
          gray[p + w - 1] +
          gray[p + w + 1];
      final gy =
          -gray[p - w - 1] -
          2 * gray[p - w] -
          gray[p - w + 1] +
          gray[p + w - 1] +
          2 * gray[p + w] +
          gray[p + w + 1];
      final ax = gx.abs(), ay = gy.abs(), value = ax + ay;
      magnitude[p] = value;
      maximum = math.max(maximum, value);
      direction[p] = ay * 100 <= ax * 41
          ? 0
          : ax * 100 <= ay * 41
          ? 1
          : gx * gy >= 0
          ? 2
          : 3;
    }
  }
  final high = (maximum * .25).clamp(30, 100), low = high * .4;
  final edges = Uint8List(w * h), queue = Int32List(w * h);
  var head = 0, tail = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final p = y * w + x, m = magnitude[p];
      if (m < low) continue;
      final delta = switch (direction[p]) {
        0 => 1,
        1 => w,
        2 => w + 1,
        _ => w - 1,
      };
      if (m < magnitude[p - delta] || m < magnitude[p + delta]) continue;
      if (m >= high) {
        edges[p] = 2;
        queue[tail++] = p;
      } else {
        edges[p] = 1;
      }
    }
  }
  while (head < tail) {
    final p = queue[head++], x = p % w, y = p ~/ w;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (x + dx < 0 || x + dx >= w || y + dy < 0 || y + dy >= h) continue;
        final n = p + dy * w + dx;
        if (edges[n] == 1) {
          edges[n] = 2;
          queue[tail++] = n;
        }
      }
    }
  }
  for (var i = 0; i < edges.length; i++) {
    edges[i] = edges[i] == 2 ? 1 : 0;
  }
  return edges;
}
