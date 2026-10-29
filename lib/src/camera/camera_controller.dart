import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kDebugMode;
import '../capture/auto_capture_controller.dart';
import '../capture/captured_document.dart';
import '../capture/crop_pipeline.dart';
import '../capture/capture_cancellation.dart';
import '../detection/quality_analyzer.dart';
import '../diagnostics/capture_diagnostics.dart';
import '../platform/windows_ffi/platform_guard.dart';
import '../preview/document_camera_preview.dart';
import '../preview/document_preview_status.dart';
import '../warnings/preview_warning.dart';
import 'camera_backend.dart';
import 'frame_source.dart';
import 'analysis_gate.dart';

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
    this.enableDebugLogging =
        kDebugMode || const bool.fromEnvironment('DOC_CAPTURE_LOGS'),
    this.analysisInterval = const Duration(milliseconds: 100),
  }) : _source = CameraBackend.requireSelected(frameSource),
       _auto = autoCapture ?? AutoCaptureController(),
       _verifyPlatform = verifyWindowsX64;

  /// Explicit harness for synthetic-frame tests; not a supported Linux runtime.
  @visibleForTesting
  WindowsDocCapture.testing({
    required FrameSource frameSource,
    AutoCaptureController? autoCapture,
    this.cropPipeline = const CropPipeline(),
    this.enableDebugLogging = false,
    this.analysisInterval = const Duration(milliseconds: 100),
  }) : _source = frameSource,
       _auto = autoCapture ?? AutoCaptureController(),
       _verifyPlatform = _testPlatform;
  static Future<void> _testPlatform() async {}
  final FrameSource _source;
  final AutoCaptureController _auto;
  final CropPipeline cropPipeline;

  /// Local JSON lines via debugPrint. Enabled by default in debug builds.
  /// Set true (or --dart-define=DOC_CAPTURE_LOGS=true) for profile/release tests.
  final bool enableDebugLogging;
  late final _diagnostics = CaptureDiagnostics(enabled: enableDebugLogging);
  Timer? _diagnosticTimer;

  void _logHealth() {
    if (!enableDebugLogging) return;
    try {
      _diagnostics.health(
        currentPreviewStatus,
        running: _running,
        nativeFps: _running ? deliveredPreviewFps : null,
        autoEnabled: _autoEnabled,
        autoState: _auto.state.name,
        stableFrames: _auto.stableFrames,
        feedbackProgress: _auto.feedbackProgress,
        bitmap: _source is BitmapPreviewDiagnostics
            ? (_source as BitmapPreviewDiagnostics).bitmapPreviewMetrics
            : null,
      );
    } catch (error, stack) {
      _diagnostics.error('diagnostic_health', error, stack);
    }
  }

  /// Upper bound on analysis frequency, independent of native preview FPS.
  final Duration analysisInterval;
  static WindowsDocCapture? _cameraOwner;
  Future<List<CameraDevice>>? _listing;
  Future<void>? _disposing;
  CaptureCancellation? _captureCancellation;
  late final _analysisGate = AnalysisGate(analysisInterval);

  void _claimCamera() {
    if (_cameraOwner != null) {
      _diagnostics.event('camera_conflict');
      throw StateError(
        _cameraOwner == this
            ? 'Previous camera cleanup is pending; await stop before reopening'
            : 'Another document camera session is active',
      );
    }
    _cameraOwner = this;
  }

  bool _canAnalyze(DocumentQualityAnalyzer analyzer) =>
      !_disposed &&
      _stopping == null &&
      _capture == null &&
      analyzer.canAcceptFrame;

  bool _requestAnalysis(DocumentQualityAnalyzer analyzer) {
    if (!_canAnalyze(analyzer)) {
      _analysisGate.discardRequest();
      return false;
    }
    return _analysisGate.request(_clock.elapsed);
  }

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
  bool _notificationsClosed = false;
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
    _diagnostics.event('auto_capture', {'enabled': value});
  }

  Future<List<CameraDevice>> listDevices() async {
    if (_disposed) throw StateError('Capture disposed');
    if (_running ||
        _starting != null ||
        _stopping != null ||
        _listing != null) {
      _diagnostics.event('enumeration_rejected', {'reason': 'session_busy'});
      throw StateError('Stop the camera before enumerating devices');
    }
    _claimCamera();
    final future = _listDevices();
    _listing = future;
    _diagnostics.event('enumeration_start');
    var releaseOwner = true;
    try {
      final devices = await future;
      _diagnostics.event('enumeration_complete', {'count': devices.length});
      return devices;
    } catch (error, stack) {
      _diagnostics.error('enumeration', error, stack);
      // A failed enumeration can include a failed native session disposal.
      // Keep the lease if cleanup still fails; another controller must not open.
      try {
        await _source.stop();
      } catch (cleanupError, cleanupStack) {
        releaseOwner = false;
        _diagnostics.error('enumeration_cleanup', cleanupError, cleanupStack);
      }
      rethrow;
    } finally {
      _listing = null;
      if (releaseOwner && _cameraOwner == this) _cameraOwner = null;
    }
  }

  Future<List<CameraDevice>> _listDevices() async {
    await _verifyPlatform();
    if (_disposed) throw StateError('Capture disposed');
    return _source.listDevices();
  }

  Widget buildPreview({
    bool showDocumentCorners = true,
    BoxFit fit = BoxFit.contain,
    Alignment alignment = Alignment.center,
    Color validColor = const Color(0xff69f0ae),
    Color warningColor = const Color(0xffffffff),
    double strokeWidth = 3,
    double cornerLength = 24,
    double cornerRadius = 0,
    DocumentFrameStyle frameStyle = DocumentFrameStyle.corners,
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
    cornerRadius: cornerRadius,
    frameStyle: frameStyle,
  );

  /// Starts one camera session. Omit [saveDirectory] to keep manual and
  /// automatic JPEG outputs in memory. Supplying it explicitly persists crops;
  /// temporary-file behavior of a custom FrameSource is owned by that source.
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
    if (_running || _starting != null || _listing != null) {
      _diagnostics.event('start_rejected', {'reason': 'session_busy'});
      throw StateError('Camera already starting or running');
    }
    if (analysisInterval < Duration.zero) {
      throw ArgumentError.value(analysisInterval, 'analysisInterval');
    }
    _claimCamera();
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
    _diagnostics.resetSession();
    _diagnostics.event('start', {
      'backend': _source.runtimeType.toString(),
      'os': Platform.operatingSystem,
      'processors': Platform.numberOfProcessors,
      'preset': preset.name,
      'specificDeviceRequested': device != null,
      'auto': auto,
      'saving': directory != null,
      'analysisIntervalMs': analysisInterval.inMilliseconds,
      'analysisMaxSide': cropPipeline.analysisWidth,
      'jpegQuality': cropPipeline.jpegQuality,
      'blurThreshold': _auto.thresholds.blurThreshold,
      'brightnessRange': [
        _auto.thresholds.minimumBrightness,
        _auto.thresholds.maximumBrightness,
      ],
      'maxClipping': _auto.thresholds.maximumClipping,
      'minimumCoverage': _auto.thresholds.minimumCoverage,
      'minimumMargin': _auto.thresholds.minimumMargin,
      'maximumTilt': _auto.thresholds.maximumTilt,
      'stableFrameCount': _auto.stableFrameCount,
      'feedbackMs': _auto.feedbackDuration.inMilliseconds,
      'maxFrameGapMs': _auto.maxFrameGap.inMilliseconds,
      'maximumMotion': _auto.maximumMotion,
      'outputMaxSide': cropPipeline.maxOutputDimension,
      'imageFilter': cropPipeline.imageFilter.name,
      'cropPadding': cropPipeline.cropPadding,
    });
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
    try {
      final analyzer = DocumentQualityAnalyzer(
        maxWidth: cropPipeline.analysisWidth,
      );
      _analyzer = analyzer;
      _analysisGate.reset();
      final source = _source;
      if (source is AnalysisDemandSource) {
        (source as AnalysisDemandSource).analysisWanted = () =>
            _requestAnalysis(analyzer);
      }
      if (source is PreviewSamplingSource) {
        (source as PreviewSamplingSource).previewSamplingAllowed = () =>
            _running && !_disposed && _stopping == null && _capture == null;
      }
      await _verifyPlatform();
      if (_disposed || _stopping != null) {
        throw StateError('Camera start cancelled');
      }
      await analyzer.start();
      if (_disposed || _stopping != null) {
        throw StateError('Camera start cancelled');
      }
      _reports = analyzer.reports.listen(
        (report) => _onReport(report, epoch),
        onError: (Object error, StackTrace stack) =>
            _onStreamError(error, stack, 'analyzer_stream'),
      );
      _frames = _source.frames.listen(
        (frame) {
          final wanted =
              _canAnalyze(analyzer) && _analysisGate.canSubmit(_clock.elapsed);
          _diagnostics.frame(submitted: wanted);
          if (!wanted) {
            _analysisGate.discardRequest();
            return;
          }
          _analysisGate.submitted(_clock.elapsed);
          analyzer.add(frame);
        },
        onError: (Object error, StackTrace stack) =>
            _onStreamError(error, stack),
        onDone: () => _onStreamError(StateError('Camera stream closed')),
      );
      await _source.start(deviceId: device, preset: preset);
      if (_disposed || _stopping != null) {
        throw StateError('Camera start cancelled');
      }
      if (_startupError != null) throw _startupError!;
      _running = true;
      _diagnostics.event('started', {
        'previewSize': [previewSize.width, previewSize.height],
      });
      if (enableDebugLogging) {
        _diagnosticTimer = Timer.periodic(
          const Duration(seconds: 5),
          (_) => _logHealth(),
        );
      }
      // Rebuild a preview mounted before start() with the negotiated dimensions.
      _publishPreview(
        DocumentPreviewStatus(state: DocumentPreviewState.processing),
      );
    } catch (error, stack) {
      _running = false;
      _diagnostics.error('start', error, stack);
      _publishPreview(
        DocumentPreviewStatus(
          state: _disposed || _stopping != null
              ? DocumentPreviewState.idle
              : DocumentPreviewState.error,
        ),
      );
      await _cleanup();
      rethrow;
    }
  }

  void _onStreamError(
    Object error, [
    StackTrace? stack,
    String stage = 'camera_stream',
  ]) {
    _diagnostics.error(stage, error, stack);
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
        _diagnostics.error('stream_cleanup', e);
        if (!_disposed) _errors.add(e);
      }),
    );
  }

  void _onReport(QualityReport report, int epoch) {
    if (!_running || epoch != _epoch) return;
    final age = DateTime.now().difference(report.capturedAt);
    if (age > _previewMaxAge || age < const Duration(seconds: -1)) {
      if (enableDebugLogging) _diagnostics.stale++;
      _auto.invalidateFrames();
      _expirePreview(epoch);
      return;
    }
    _diagnostics.report(report);
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
    if (enableDebugLogging) _diagnostics.expired++;
    _auto.invalidateFrames();
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
    if (_notificationsClosed) return;
    final previous = _previewStatus.value;
    final changed = previous.state != value.state;
    _previewStatus.value = value;
    if (identical(_previewStatus.value, value)) {
      _diagnostics.state(previous, value);
    }
    if (changed && !_disposed && identical(_previewStatus.value, value)) {
      try {
        _onDocumentStateChanged?.call(value.state);
      } catch (error, stack) {
        _diagnostics.error('preview_callback', error, stack);
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
        try {
          _callback?.call(captured);
        } catch (error, stack) {
          _diagnostics.error('auto_capture_callback', error, stack);
          rethrow;
        }
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
    if (!_running || _disposed || _stopping != null || _capture != null) {
      _diagnostics.event('capture_skipped', {
        'reason': _capture != null ? 'busy' : 'session_inactive',
      });
      return null;
    }
    _diagnostics.event('capture_start', {'auto': auto});
    final epoch = _epoch;
    final cancellation = CaptureCancellation();
    _captureCancellation = cancellation;
    final future = _captureFrame(auto, expectedQuad, cancellation);
    _capture = future;
    _publishCapturePhase(DocumentPreviewState.capturing);
    try {
      final result = await future;
      final active = _running && !_disposed && epoch == _epoch;
      _diagnostics.event('capture_complete', {
        'outcome': !active || cancellation.isCancelled
            ? 'cancelled'
            : result == null
            ? 'rejected'
            : 'success',
        if (result != null && active) ...{
          'processingMs': result.processingTime.inMilliseconds,
          'originalBytes': result.originalJpeg.length,
          'croppedBytes': result.croppedJpeg.length,
          'saved': result.savedPath != null,
        },
      });
      return active ? result : null;
    } catch (error, stack) {
      _diagnostics.error('capture', error, stack);
      rethrow;
    } finally {
      _captureCancellation = null;
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
    CaptureCancellation cancellation,
  ) async {
    final frame = await cancellation.wait(
      _source.latestFullResolutionFrame().timeout(const Duration(seconds: 15)),
    );
    if (cancellation.isCancelled) return null;
    if (frame != null) {
      _diagnostics.event('snapshot', {
        'size': [frame.width, frame.height],
      });
    }
    final age = frame == null
        ? Duration.zero
        : DateTime.now().difference(frame.capturedAt);
    if (frame == null ||
        age > const Duration(milliseconds: 500) ||
        age < const Duration(seconds: -1)) {
      _diagnostics.event('snapshot_rejected', {
        'reason': frame == null ? 'missing' : 'timestamp',
        'ageMs': age.inMilliseconds,
      });
      return null;
    }
    return cropPipeline.capture(
      frame,
      saveDirectory: _directory,
      requiredQuality: auto ? _auto.thresholds : null,
      expectedNormalizedQuad: expectedQuad,
      maximumMotion: _auto.maximumMotion,
      cancellation: cancellation,
      onDiagnostic: enableDebugLogging ? _diagnostics.event : null,
    );
  }

  Future<void> stop() =>
      _disposed ? dispose() : _stopSession(DocumentPreviewState.idle);

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
    _diagnostics.event('stop', {
      'starting': _starting != null,
      'capturing': _capture != null,
    });
    _diagnosticTimer?.cancel();
    _diagnosticTimer = null;
    if (_starting != null) {
      try {
        await _starting;
      } catch (_) {
        // Startup attempted cleanup, but it may have failed. Verify/retry below
        // instead of reporting a successful handoff while native remains open.
      }
    }
    _logHealth(); // Preserve the final fresh quality snapshot before idle clears it.
    _running = false;
    ++_epoch;
    _captureCancellation?.cancel();
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
    _diagnostics.event('stopped');
  }

  Future<void> _cleanup() async {
    _previewExpiry?.cancel();
    Object? failure;
    StackTrace? failureStack;
    Future<void> attempt(String stage, Future<void> Function() cleanup) async {
      try {
        await cleanup();
      } catch (error, stack) {
        _diagnostics.error(stage, error, stack);
        failure ??= error;
        failureStack ??= stack;
      }
    }

    final frames = _frames, reports = _reports, analyzer = _analyzer;
    _frames = null;
    _reports = null;
    _analyzer = null;
    if (frames != null) await attempt('frames_cancel', frames.cancel);
    if (reports != null) await attempt('reports_cancel', reports.cancel);
    if (analyzer != null) await attempt('analyzer_dispose', analyzer.dispose);
    if (_cameraOwner == this) {
      final source = _source;
      if (source is AnalysisDemandSource) {
        (source as AnalysisDemandSource).analysisWanted = null;
      }
      var stopped = false;
      await attempt('camera_stop', () async {
        await _source.stop();
        stopped = true;
      });
      if (source is PreviewSamplingSource) {
        (source as PreviewSamplingSource).previewSamplingAllowed = null;
      }
      if (stopped && _cameraOwner == this) {
        _cameraOwner = null;
      } else if (!stopped) {
        _diagnostics.event('camera_cleanup_pending');
      }
    }
    _callback = null;
    _directory = null;
    _onDocumentStateChanged = null;
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  }

  Future<void> dispose() {
    if (_disposing != null) return _disposing!;
    final completion = Completer<void>();
    _disposing = completion.future;
    unawaited(
      _dispose().then(
        completion.complete,
        onError: (Object error, StackTrace stack) {
          // Remain terminal, but allow a later dispose/stop to retry native cleanup.
          // Concurrent callers still share the same in-flight future.
          if (identical(_disposing, completion.future)) _disposing = null;
          _diagnostics.error('dispose', error, stack);
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  Future<void> _dispose() async {
    _disposed = true;
    _diagnostics.event('dispose');
    try {
      if (_listing != null) {
        try {
          await _listing;
        } catch (_) {
          /* enumeration caller receives error */
        }
      }
      await _stopSession(DocumentPreviewState.idle);
    } finally {
      if (!_notificationsClosed) {
        _notificationsClosed = true;
        await _warnings.close();
        await _statuses.close();
        await _errors.close();
        _onDocumentStateChanged = null;
        _previewStatus.dispose();
      }
    }
    _diagnostics.event('disposed');
  }
}
