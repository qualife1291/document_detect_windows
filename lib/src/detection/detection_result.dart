import 'dart:ui';

enum DocumentKind { a4, idCard, unknown }

class DetectionResult {
  DetectionResult({
    required this.hasDocument,
    List<Offset>? quad,
    this.coverageRatio = 0,
    this.tiltAngle = 0,
    this.edgeMargin = 0,
    this.blurScore = 0,
    this.brightnessScore = 0,
    this.clippingRatio = 0,
    this.kind = DocumentKind.unknown,
  }) : quad = quad == null ? null : List.unmodifiable(quad);
  factory DetectionResult.empty() => DetectionResult(hasDocument: false);
  final bool hasDocument;

  /// Clockwise TL, TR, BR, BL in the input frame's pixel coordinates.
  final List<Offset>? quad;
  final double coverageRatio;
  final double tiltAngle;
  final double edgeMargin;
  final double blurScore;
  final double brightnessScore;
  final double clippingRatio;
  final DocumentKind kind;
}
