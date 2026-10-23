import 'dart:typed_data';
import 'dart:ui';

class CapturedDocument {
  CapturedDocument({
    required this.originalJpeg,
    required this.croppedJpeg,
    required List<Offset> quad,
    List<Offset>? cropQuad,
    required this.blurScore,
    required this.coverageRatio,
    required this.capturedAt,
    this.savedPath,
    this.processingTime = Duration.zero,
  }) : quad = List.unmodifiable(quad),
       cropQuad = List.unmodifiable(cropQuad ?? quad);
  final Uint8List originalJpeg, croppedJpeg;

  /// Detected document corners, before optional crop padding, in source pixels.
  final List<Offset> quad;

  /// Actual source-pixel corners used to produce [croppedJpeg]. Includes the
  /// bounded crop padding. Older manually constructed results default to [quad].
  final List<Offset> cropQuad;
  final double blurScore, coverageRatio;
  final DateTime capturedAt;
  final String? savedPath;

  /// Fresh snapshot through detection, perspective correction, JPEG and file IO.
  final Duration processingTime;
}
