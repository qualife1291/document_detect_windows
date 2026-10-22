import 'dart:typed_data';
import 'package:flutter/widgets.dart';

enum ResolutionPreset { medium, high, veryHigh }

class CameraDevice {
  const CameraDevice({required this.id, required this.name});
  final String id;
  final String name;
}

/// Owned, unmirrored, top-left-origin RGBA pixels. The producer must not mutate
/// [rgba] after delivery. Preview is rendered separately by the native texture.
class FrameBuffer {
  FrameBuffer({
    required this.width,
    required this.height,
    required this.rgba,
    required this.capturedAt,
    required this.sequence,
  }) {
    if (width < 2 ||
        height < 2 ||
        width * height > 33554432 ||
        rgba.length != width * height * 4) {
      throw ArgumentError('Invalid RGBA frame dimensions or length');
    }
  }
  final int width;
  final int height;
  final Uint8List rgba;
  final DateTime capturedAt;
  final int sequence;
}

abstract class FrameSource {
  Future<List<CameraDevice>> listDevices();
  Future<void> start({
    String? deviceId,
    ResolutionPreset preset = ResolutionPreset.high,
  });
  Future<void> stop();
  Stream<FrameBuffer> get frames;

  /// A fresh full-resolution snapshot, never the downsampled analysis buffer.
  Future<FrameBuffer?> latestFullResolutionFrame();

  /// Native texture only; this must never render streamed Dart frame bytes.
  Widget buildPreview();
  Size get previewSize;
}

/// Optional diagnostics from native delivery counters. This is not a measured
/// sensor-to-screen latency or a count of frames composited by Flutter.
abstract interface class FrameSourceDiagnostics {
  double? get deliveredPreviewFps;
}
