import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import '../capture/auto_capture_controller.dart';
import '../capture/captured_document.dart';
import '../capture/crop_pipeline.dart';
import '../detection/quality_analyzer.dart';
import '../platform/windows_ffi/platform_guard.dart';
import '../preview/document_camera_preview.dart';
import '../preview/document_preview_status.dart';
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
  final _previewStatus = ValueNotifier<DocumentPreviewStatus>(
    DocumentPreviewStatus(state: DocumentPreviewState.idle),
  );
  Timer? _previewExpiry;
  ValueChanged<DocumentPreviewState>? _onDocumentStateChanged;
  static const _previewMaxAge = Duration(milliseconds: 500);
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

  /// Updates on every accepted detection, including corner motion when the
  /// primary enum state stays unchanged. Listen with ValueListenableBuilder.
  ValueListenable<DocumentPreviewStatus> get previewStatus => _previewStatus;
  DocumentPreviewStatus get currentPreviewStatus => _previewStatus.value;
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

  Widget buildPreview({
    bool showDocumentCorners = true,
    BoxFit fit = BoxFit.contain,
    Alignment alignment = Alignment.center,
    Color validColor = const Color(0xff69f0ae),
    Color warningColor = const Color(0xffffcc80),
    double strokeWidth = 3,
    double cornerLength = 24,
  }) => DocumentCameraPreview(
    frameSource: _source,
    status: previewStatus,
    showDocumentCorners: showDocumentCorners,
    fit: fit,
    alignment: alignment,
    validColor: validColor,
    warningColor: warningColor,
    strokeWidth: strokeWidth,
    cornerLength: cornerLength,
  );

  Future<void> start({
    String? deviceId,
    ResolutionPreset preset = ResolutionPreset.high,
    bool enableAutoCapture = true,
    String? saveDirectory,
    void Function(CapturedDocument)? onAutoCapture,
    ValueChanged<DocumentPreviewState>? onDocumentStateChanged,
  }) async {
    if (_disposed) throw StateError('Capture disposed');
    if (_stopping != null) await _stopping;
    if (_disposed) throw StateError('Capture disposed');
    if (_running || _starting != null) {
      throw StateError('Camera already starting or running');
    }
    _onDocumentStateChanged = onDocumentStateChanged;
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
    // Settle _starting before notifying consumer callbacks, which can stop().
    await Future<void>.value();
    _publishPreview(
      DocumentPreviewStatus(state: DocumentPreviewState.processing),
    );
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
      await _verifyPlatform();
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
      // Rebuild a preview mounted before start() with the negotiated dimensions.
      _publishPreview(
        DocumentPreviewStatus(state: DocumentPreviewState.processing),
      );
    } catch (_) {
      _publishPreview(DocumentPreviewStatus(state: DocumentPreviewState.error));
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
    _previewExpiry?.cancel();
    _publishPreview(DocumentPreviewStatus(state: DocumentPreviewState.error));
    _errors.add(error);
    // Fail closed after device loss; discard stale frames and restart explicitly.
    unawaited(
      _stopSession(DocumentPreviewState.error).catchError((Object e) {
        if (!_disposed) _errors.add(e);
      }),
    );
  }

  void _onReport(QualityReport report, int epoch) {
    if (!_running || epoch != _epoch) return;
    final age = DateTime.now().difference(report.capturedAt);
    if (age > _previewMaxAge || age < const Duration(seconds: -1)) {
      _auto.reset();
      _expirePreview(epoch);
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
    final phase = _capture != null || trigger
        ? DocumentPreviewState.capturing
        : _autoEnabled && _auto.state == AutoCaptureState.cooldown
        ? DocumentPreviewState.cooldown
        : null;
    _publishPreview(
      DocumentPreviewStatus.fromReport(
        report,
        warnings: warnings,
        state: phase,
      ),
    );
    if (!_running || epoch != _epoch) return;
    _previewExpiry?.cancel();
    final remaining = _previewMaxAge - (age.isNegative ? Duration.zero : age);
    _previewExpiry = Timer(remaining, () => _expirePreview(epoch));
    if (trigger) unawaited(_performAutoCapture(epoch, q!));
  }

  void _expirePreview(int epoch) {
    if (!_running || epoch != _epoch) return;
    _auto.reset();
    _previewExpiry?.cancel();
    _publishPreview(
      DocumentPreviewStatus(
        state: _capture != null
            ? DocumentPreviewState.capturing
            : DocumentPreviewState.processing,
      ),
    );
  }

  void _publishPreview(DocumentPreviewStatus value) {
    final changed = _previewStatus.value.state != value.state;
    _previewStatus.value = value;
    if (changed && !_disposed && identical(_previewStatus.value, value)) {
      try {
        _onDocumentStateChanged?.call(value.state);
      } catch (error) {
        // An integration callback must not interrupt camera/detection cleanup.
        _errors.add(error);
      }
    }
  }

  void _publishCapturePhase(DocumentPreviewState state) {
    final previous = currentPreviewStatus;
    final report = previous.report;
    final fresh =
        report != null &&
        DateTime.now().difference(report.capturedAt) <= _previewMaxAge;
    _publishPreview(
      DocumentPreviewStatus(
        state: state,
        normalizedQuad: fresh ? previous.normalizedQuad : null,
        warnings: fresh ? previous.warnings : const [],
        report: fresh ? report : null,
      ),
    );
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
    final epoch = _epoch;
    final future = _captureFrame(auto, expectedQuad);
    _capture = future;
    _publishCapturePhase(DocumentPreviewState.capturing);
    try {
      return await future;
    } finally {
      _capture = null;
      _auto.captureCompleted(_clock.elapsed);
      if (_running && epoch == _epoch && !_disposed) {
        _publishCapturePhase(DocumentPreviewState.cooldown);
      }
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

  Future<void> stop() => _disposed
      ? Future<void>.value()
      : _stopSession(DocumentPreviewState.idle);

  Future<void> _stopSession(DocumentPreviewState finalState) {
    final pending = _stopping;
    if (pending != null) return pending;
    final completion = Completer<void>();
    // Install the shared future before idle/error notifications can reenter stop.
    _stopping = completion.future;
    unawaited(_completeStop(finalState, completion));
    return completion.future;
  }

  Future<void> _completeStop(
    DocumentPreviewState finalState,
    Completer<void> completion,
  ) async {
    try {
      await _stop(finalState);
      completion.complete();
    } catch (error, stack) {
      completion.completeError(error, stack);
    } finally {
      _stopping = null;
    }
  }

  Future<void> _stop(DocumentPreviewState finalState) async {
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
    _previewExpiry?.cancel();
    _publishPreview(DocumentPreviewStatus(state: finalState));
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
    _previewExpiry?.cancel();
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
      await _stopSession(DocumentPreviewState.idle);
    } finally {
      await _warnings.close();
      await _statuses.close();
      await _errors.close();
      _onDocumentStateChanged = null;
      _previewStatus.dispose();
    }
  }
}
