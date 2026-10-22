import 'dart:async';
import 'package:flutter/widgets.dart';
import '../capture/auto_capture_controller.dart';
import '../capture/captured_document.dart';
import '../capture/crop_pipeline.dart';
import '../detection/quality_analyzer.dart';
import '../platform/windows_ffi/platform_guard.dart';
import '../warnings/preview_warning.dart';
import 'camera_backend.dart';
import 'frame_source.dart';

class CaptureStatus {
  const CaptureStatus({
    required this.report,
    required this.state,
    required this.feedbackProgress,
    required this.warnings,
    required this.detectionFps,
  });
  final QualityReport report;
  final AutoCaptureState state;
  final double feedbackProgress, detectionFps;
  final List<PreviewWarning> warnings;
}

class WindowsDocCapture {
  WindowsDocCapture({
    FrameSource? frameSource,
    AutoCaptureController? autoCapture,
    this.cropPipeline = const CropPipeline(),
  }) : _source = CameraBackend.requireSelected(frameSource),
       _auto = autoCapture ?? AutoCaptureController(),
       _verifyPlatform = verifyWindowsX64;

  /// Explicit harness for synthetic-frame tests; not a supported Linux runtime.
  @visibleForTesting
  WindowsDocCapture.testing({
    required FrameSource frameSource,
    AutoCaptureController? autoCapture,
    this.cropPipeline = const CropPipeline(),
  }) : _source = frameSource,
       _auto = autoCapture ?? AutoCaptureController(),
       _verifyPlatform = _testPlatform;
  static Future<void> _testPlatform() async {}
  final FrameSource _source;
  final AutoCaptureController _auto;
  final CropPipeline cropPipeline;
  final Future<void> Function() _verifyPlatform;
  final _warnings = StreamController<PreviewWarning>.broadcast();
  final _statuses = StreamController<CaptureStatus>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  final _clock = Stopwatch()..start();
  DocumentQualityAnalyzer? _analyzer;
  StreamSubscription<FrameBuffer>? _frames;
  StreamSubscription<QualityReport>? _reports;
  Future<void>? _starting, _stopping;
  Future<CapturedDocument?>? _capture;
  bool _running = false, _disposed = false, _autoEnabled = true;
  int _epoch = 0, _reportsCount = 0;
  Duration _fpsStart = Duration.zero;
  String? _directory;
  Object? _startupError;
  void Function(CapturedDocument)? _callback;

  Stream<PreviewWarning> get warnings => _warnings.stream;
  Stream<CaptureStatus> get statuses => _statuses.stream;
  Stream<Object> get errors => _errors.stream;
  Size get previewSize => _source.previewSize;
  bool get isRunning => _running;
  double? get deliveredPreviewFps {
    final source = _source;
    return source is FrameSourceDiagnostics
        ? (source as FrameSourceDiagnostics).deliveredPreviewFps
        : null;
  }

  set autoCaptureEnabled(bool value) {
    _autoEnabled = value;
    _auto.reset();
  }

  Future<List<CameraDevice>> listDevices() async {
    await _verifyPlatform();
    return _source.listDevices();
  }

  Widget buildPreview() => _source.buildPreview();

  Future<void> start({
    String? deviceId,
    ResolutionPreset preset = ResolutionPreset.high,
    bool enableAutoCapture = true,
    String? saveDirectory,
    void Function(CapturedDocument)? onAutoCapture,
  }) async {
    if (_disposed) throw StateError('Capture disposed');
    if (_stopping != null) await _stopping;
    if (_disposed) throw StateError('Capture disposed');
    if (_running || _starting != null) {
      throw StateError('Camera already starting or running');
    }
    final future = _start(
      deviceId,
      preset,
      enableAutoCapture,
      saveDirectory,
      onAutoCapture,
    );
    _starting = future;
    try {
      await future;
    } finally {
      _starting = null;
    }
  }

  Future<void> _start(
    String? device,
    ResolutionPreset preset,
    bool auto,
    String? directory,
    void Function(CapturedDocument)? callback,
  ) async {
    await _verifyPlatform();
    _directory = directory;
    _startupError = null;
    _callback = callback;
    _autoEnabled = auto;
    _auto.reset();
    _reportsCount = 0;
    _fpsStart = _clock.elapsed;
    final epoch = ++_epoch;
    final analyzer = DocumentQualityAnalyzer(
      maxWidth: cropPipeline.analysisWidth,
    );
    _analyzer = analyzer;
    try {
      await analyzer.start();
      _reports = analyzer.reports.listen(
        (report) => _onReport(report, epoch),
        onError: _onStreamError,
      );
      _frames = _source.frames.listen(
        analyzer.add,
        onError: _onStreamError,
        onDone: () => _onStreamError(StateError('Camera stream closed')),
      );
      await _source.start(deviceId: device, preset: preset);
      if (_startupError != null) throw _startupError!;
      _running = true;
    } catch (_) {
      await _cleanup();
      rethrow;
    }
  }

  void _onStreamError(Object error) {
    if (!_running) {
      if (_starting != null) _startupError = error;
      return;
    }
    _auto.reset();
    _errors.add(error);
    // Fail closed after device loss; discard stale frames and restart explicitly.
    unawaited(
      stop().catchError((Object e) {
        if (!_disposed) _errors.add(e);
      }),
    );
  }

  void _onReport(QualityReport report, int epoch) {
    if (!_running || epoch != _epoch) return;
    final age = DateTime.now().difference(report.capturedAt);
    if (age > const Duration(milliseconds: 500) ||
        age < const Duration(seconds: -1)) {
      _auto.reset();
      return;
    }
    final result = report.result;
    final warnings = _auto.thresholds.warningsFor(result);
    for (final warning in warnings) {
      _warnings.add(warning);
    }
    final q = result.quad
        ?.map(
          (p) => Offset(
            p.dx / report.frameSize.width,
            p.dy / report.frameSize.height,
          ),
        )
        .toList();
    final trigger =
        _autoEnabled &&
        _capture == null &&
        _auto.update(result, q, _clock.elapsed);
    _reportsCount++;
    final seconds = (_clock.elapsed - _fpsStart).inMicroseconds / 1e6;
    _statuses.add(
      CaptureStatus(
        report: report,
        state: _auto.state,
        feedbackProgress: _auto.feedbackProgress,
        warnings: warnings,
        detectionFps: seconds > 0 ? _reportsCount / seconds : 0,
      ),
    );
    if (trigger) unawaited(_performAutoCapture(epoch, q!));
  }

  Future<void> _performAutoCapture(int epoch, List<Offset> expectedQuad) async {
    try {
      final captured = await _takeCapture(
        auto: true,
        expectedQuad: expectedQuad,
      );
      if (captured != null && _running && epoch == _epoch) {
        _callback?.call(captured);
      }
    } catch (e) {
      if (!_disposed) _errors.add(e);
    }
  }

  Future<CapturedDocument?> captureNow() => _takeCapture(auto: false);
  Future<CapturedDocument?> _takeCapture({
    required bool auto,
    List<Offset>? expectedQuad,
  }) async {
    if (!_running || _disposed || _capture != null) return null;
    final future = _captureFrame(auto, expectedQuad);
    _capture = future;
    try {
      return await future;
    } finally {
      _capture = null;
      _auto.captureCompleted(_clock.elapsed);
    }
  }

  Future<CapturedDocument?> _captureFrame(
    bool auto,
    List<Offset>? expectedQuad,
  ) async {
    final frame = await _source.latestFullResolutionFrame();
    if (frame == null ||
        DateTime.now().difference(frame.capturedAt) >
            const Duration(milliseconds: 500)) {
      return null;
    }
    return cropPipeline.capture(
      frame,
      saveDirectory: _directory,
      requiredQuality: auto ? _auto.thresholds : null,
      expectedNormalizedQuad: expectedQuad,
      maximumMotion: _auto.maximumMotion,
    );
  }

  Future<void> stop() async {
    if (_stopping != null) return _stopping;
    final future = _stop();
    _stopping = future;
    try {
      await future;
    } finally {
      _stopping = null;
    }
  }

  Future<void> _stop() async {
    if (_starting != null) {
      try {
        await _starting;
      } catch (_) {
        return;
      }
    }
    _running = false;
    ++_epoch;
    _auto.reset();
    final capture = _capture;
    if (capture != null) {
      try {
        await capture;
      } catch (_) {
        /* capture caller receives errors */
      }
    }
    await _cleanup();
  }

  Future<void> _cleanup() async {
    await _frames?.cancel();
    _frames = null;
    await _reports?.cancel();
    _reports = null;
    await _analyzer?.dispose();
    _analyzer = null;
    await _source.stop();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await stop();
    } finally {
      await _warnings.close();
      await _statuses.close();
      await _errors.close();
    }
  }
}
