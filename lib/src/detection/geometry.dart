import 'dart:math' as math;
import 'dart:ui';

double cross(Offset a, Offset b, Offset c) =>
    (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);

double polygonArea(List<Offset> q) {
  double sum = 0;
  for (var i = 0; i < q.length; i++) {
    final b = q[(i + 1) % q.length];
    sum += q[i].dx * b.dy - b.dx * q[i].dy;
  }
  return sum.abs() / 2;
}

List<Offset> convexHull(List<Offset> points) {
  points.sort(
    (a, b) => a.dx == b.dx ? a.dy.compareTo(b.dy) : a.dx.compareTo(b.dx),
  );
  final lower = <Offset>[], upper = <Offset>[];
  for (final p in points) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  for (final p in points.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  if (lower.length < 2) return lower;
  return [...lower.take(lower.length - 1), ...upper.take(upper.length - 1)];
}

List<Offset>? fitQuad(List<Offset> hull) {
  if (hull.length < 4) return null;
  final q = List<Offset>.of(hull);
  final area = polygonArea(q);
  while (q.length > 4) {
    var index = 0;
    var loss = double.infinity;
    for (var i = 0; i < q.length; i++) {
      final a = cross(
        q[(i + q.length - 1) % q.length],
        q[i],
        q[(i + 1) % q.length],
      ).abs();
      if (a < loss) {
        index = i;
        loss = a;
      }
    }
    q.removeAt(index);
  }
  // Reject circles/ellipses and contours that need substantial shape loss.
  if (polygonArea(q) < area * .88) return null;
  var first = 0;
  for (var i = 1; i < 4; i++) {
    if (q[i].dx + q[i].dy < q[first].dx + q[first].dy) first = i;
  }
  return List.generate(4, (i) => q[(i + first) % 4]);
}

double tiltOf(List<Offset> q) {
  double worst = 0;
  for (var i = 0; i < 4; i++) {
    final a = q[(i + 3) % 4] - q[i], b = q[(i + 1) % 4] - q[i];
    final angle =
        math.acos(
          ((a.dx * b.dx + a.dy * b.dy) / (a.distance * b.distance)).clamp(
            -1,
            1,
          ),
        ) *
        180 /
        math.pi;
    worst = math.max(worst, (90 - angle).abs());
  }
  return worst;
}

bool insideQuad(double x, double y, List<Offset> q) {
  for (var i = 0; i < 4; i++) {
    final a = q[i], b = q[(i + 1) % 4];
    if ((b.dx - a.dx) * (y - a.dy) - (b.dy - a.dy) * (x - a.dx) < 0) {
      return false;
    }
  }
  return true;
}
