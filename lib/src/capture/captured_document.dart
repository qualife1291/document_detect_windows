import 'dart:typed_data';
import 'dart:ui';

class CapturedDocument {
  CapturedDocument({
    required this.originalJpeg,
    required this.croppedJpeg,
    required List<Offset> quad,
    required this.blurScore,
    required this.coverageRatio,
    required this.capturedAt,
    this.savedPath,
    this.processingTime = Duration.zero,
  }) : quad = List.unmodifiable(quad);
  final Uint8List originalJpeg, croppedJpeg;
  final List<Offset> quad;
  final double blurScore, coverageRatio;
  final DateTime capturedAt;
  final String? savedPath;

  /// Fresh snapshot through detection, perspective correction, JPEG and file IO.
  final Duration processingTime;
}
