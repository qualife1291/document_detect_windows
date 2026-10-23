import 'dart:math' as math;
import 'dart:ui';
import '../detection/geometry.dart';

/// A small outward offset of the four edge lines, bounded by the source image.
/// This does not change the detection used for quality or motion checks.
class CropGeometry {
  CropGeometry._(
    this.quad,
    this.requestedPaddingPixels,
    this.appliedPaddingPixels,
  );
  final List<Offset> quad;
  final double requestedPaddingPixels, appliedPaddingPixels;
  bool get paddingLimited =>
      appliedPaddingPixels + 1e-6 < requestedPaddingPixels;

  factory CropGeometry.fromDetection(
    List<Offset> quad, {
    required int width,
    required int height,
    required double padding,
  }) {
    if (!padding.isFinite || padding < 0 || padding > .1) {
      throw ArgumentError.value(padding, 'cropPadding', 'Expected 0..0.1');
    }
    if (width < 2 ||
        height < 2 ||
        quad.length != 4 ||
        quad.any(
          (p) =>
              !p.dx.isFinite ||
              !p.dy.isFinite ||
              p.dx < 0 ||
              p.dy < 0 ||
              p.dx > width - 1 ||
              p.dy > height - 1,
        ) ||
        polygonArea(quad) < 1 ||
        List.generate(
          4,
          (i) => cross(quad[i], quad[(i + 1) % 4], quad[(i + 2) % 4]),
        ).any((c) => c <= 0)) {
      throw ArgumentError('Expected a convex clockwise in-frame quadrilateral');
    }
    final edges = List.generate(4, (i) => quad[(i + 1) % 4] - quad[i]);
    final requested = edges.map((e) => e.distance).reduce(math.min) * padding;
    if (requested == 0) return CropGeometry._(List.unmodifiable(quad), 0, 0);
    final normals = edges.map((e) => Offset(-e.dy, e.dx) / e.distance).toList();
    final constants = List.generate(
      4,
      (i) =>
          normals[i].dx * quad[i].dx + normals[i].dy * quad[i].dy - requested,
    );
    final expanded = List.generate(4, (i) {
      final previous = (i + 3) % 4;
      final a = normals[previous], b = normals[i];
      final determinant = a.dx * b.dy - a.dy * b.dx;
      return Offset(
        (constants[previous] * b.dy - a.dy * constants[i]) / determinant,
        (a.dx * constants[i] - constants[previous] * b.dx) / determinant,
      );
    });
    // One common offset keeps all four edges parallel to the detected edges.
    // Reduce it at the sensor boundary, rather than clipping individual corners
    // into a different perspective or sampling unavailable pixels.
    var fraction = 1.0;
    for (var i = 0; i < 4; i++) {
      final delta = expanded[i] - quad[i];
      if (delta.dx < 0) fraction = math.min(fraction, -quad[i].dx / delta.dx);
      if (delta.dx > 0) {
        fraction = math.min(fraction, (width - 1 - quad[i].dx) / delta.dx);
      }
      if (delta.dy < 0) fraction = math.min(fraction, -quad[i].dy / delta.dy);
      if (delta.dy > 0) {
        fraction = math.min(fraction, (height - 1 - quad[i].dy) / delta.dy);
      }
    }
    fraction = fraction.clamp(0.0, 1.0);
    final bounded = List.generate(4, (i) {
      final point = quad[i] + (expanded[i] - quad[i]) * fraction;
      return Offset(
        point.dx.clamp(0.0, width - 1.0),
        point.dy.clamp(0.0, height - 1.0),
      );
    });
    return CropGeometry._(
      List.unmodifiable(bounded),
      requested,
      requested * fraction,
    );
  }
}
