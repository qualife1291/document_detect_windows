import 'dart:typed_data';
import 'package:flutter/widgets.dart';

enum ResolutionPreset { medium, high, veryHigh }

class CameraDevice {
  const CameraDevice({required this.id, required this.name});
  final String id;
  final String name;
}

/// Owned, unmirrored, top-left-origin RGBA pixels. The producer must not mutate
/// [rgba] after delivery. Native texture preview is separate; an opt-in bounded
/// bitmap preview may share the sampled frame.
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

  /// Native texture by default. A documented opt-in fallback may display
  /// bounded, downsampled bitmap frames on devices with texture/driver issues.
  Widget buildPreview();
  Size get previewSize;
}

/// Optional diagnostics from native delivery counters. This is not a measured
/// sensor-to-screen latency or a count of frames composited by Flutter.
abstract interface class FrameSourceDiagnostics {
  double? get deliveredPreviewFps;
}

/// Optional pull backpressure. Adapters should avoid copying a high-resolution
/// native frame while analysis already has work, and while capture is running.
abstract interface class AnalysisDemandSource {
  set analysisWanted(bool Function()? wanted);
}

/// Optional control for a sampled bitmap preview. Keep the last displayed image
/// while capture/start/teardown disallow extra native readbacks.
abstract interface class PreviewSamplingSource {
  set previewSamplingAllowed(bool Function()? allowed);
}

/// Cumulative counters only, no frame history or user identifiers.
class BitmapPreviewMetrics {
  const BitmapPreviewMetrics({
    required this.elapsed,
    required this.offeredFrames,
    required this.sampledFrames,
    required this.totalSamplingTime,
    required this.maxSamplingTime,
    required this.requestedInterval,
    required this.effectiveInterval,
    this.lastOfferedAt,
    this.previewWidth = 0,
    this.previewHeight = 0,
    this.loadLevel = 0,
    this.previewInterval = Duration.zero,
    this.decodeTime = Duration.zero,
    this.uiFrameTime = Duration.zero,
  });
  final Duration elapsed, totalSamplingTime, maxSamplingTime;
  final Duration requestedInterval, effectiveInterval;
  final Duration? lastOfferedAt;
  final int offeredFrames, sampledFrames;
  final int previewWidth, previewHeight, loadLevel;
  final Duration previewInterval, decodeTime, uiFrameTime;
}

abstract interface class BitmapPreviewDiagnostics {
  BitmapPreviewMetrics? get bitmapPreviewMetrics;
}

/// Serializes native lifecycle operations, including enumeration and snapshots.
/// A failed operation does not poison subsequent cleanup/restart.
class CameraOperationQueue {
  Future<void> _tail = Future<void>.value();
  Future<T> run<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
