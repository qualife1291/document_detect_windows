import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:windows_doc_capture_uvc_backend/windows_doc_capture_uvc_backend.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';

enum UvcPreviewMode { texture, bitmap }

/// Independent from the camera/snapshot resolution preset.
enum BitmapPreviewProfile { lowResource, balanced, detail }

/// Experimental candidate. Texture is the default; bitmap is an explicit,
/// bounded low-rate fallback that does not register a Flutter external texture.
class UvcFrameSource
    implements
        FrameSource,
        FrameSourceDiagnostics,
        AnalysisDemandSource,
        PreviewSamplingSource,
        BitmapPreviewDiagnostics {
  UvcFrameSource({
    this.previewMode = UvcPreviewMode.texture,
    this.pollInterval = const Duration(milliseconds: 100),
    this.preferredNativeFps = 30,
    this.bitmapPreviewProfile = BitmapPreviewProfile.balanced,
    this.bitmapPreviewInterval = const Duration(milliseconds: 66),
  }) : _testCamera = null {
    _validateInterval();
  }
  @visibleForTesting
  UvcFrameSource.testing({
    required UvcCamera camera,
    this.previewMode = UvcPreviewMode.texture,
    this.pollInterval = const Duration(milliseconds: 100),
    this.preferredNativeFps = 30,
    this.bitmapPreviewProfile = BitmapPreviewProfile.balanced,
    this.bitmapPreviewInterval = const Duration(milliseconds: 66),
  }) : _testCamera = camera {
    _validateInterval();
  }
  final UvcPreviewMode previewMode;
  final Duration pollInterval;

  /// Requested bitmap cadence, independent of analysis. Expensive readback or
  /// a busy decoder reduces actual offers; this is not a display-FPS guarantee.
  final Duration bitmapPreviewInterval;
  final int preferredNativeFps;
  final BitmapPreviewProfile bitmapPreviewProfile;
  int get _load => _bitmapDemand?.loadLevel ?? 0;
  int get _previewMaximum => switch (bitmapPreviewProfile) {
    BitmapPreviewProfile.lowResource => 640,
    BitmapPreviewProfile.balanced => _load == 0 ? 960 : 640,
    BitmapPreviewProfile.detail =>
      _load == 0
          ? 1280
          : _load == 1
          ? 960
          : 640,
  };
  Duration get _previewInterval => Duration(
    microseconds:
        math.max(
          bitmapPreviewInterval.inMicroseconds,
          bitmapPreviewProfile == BitmapPreviewProfile.lowResource
              ? 100000
              : 50000,
        ) *
        (2 + _load) ~/
        2,
  );
  int _sampleWidth = 0, _sampleHeight = 0;
  final UvcCamera? _testCamera;
  bool _streaming = false;
  void _validateInterval() {
    if (preferredNativeFps < 10 || preferredNativeFps > 120) {
      throw ArgumentError.value(preferredNativeFps, 'preferredNativeFps');
    }
    if (bitmapPreviewInterval < const Duration(milliseconds: 50) ||
        bitmapPreviewInterval > const Duration(seconds: 1)) {
      throw ArgumentError.value(bitmapPreviewInterval, 'bitmapPreviewInterval');
    }
    if (pollInterval < const Duration(milliseconds: 50) ||
        pollInterval > const Duration(seconds: 1)) {
      throw ArgumentError.value(pollInterval, 'pollInterval');
    }
  }

  final _operations = CameraOperationQueue();
  bool Function()? _analysisWanted, _previewAllowed;
  @override
  set previewSamplingAllowed(bool Function()? allowed) =>
      _previewAllowed = allowed;
  @override
  set analysisWanted(bool Function()? wanted) => _analysisWanted = wanted;
  final _frames = StreamController<FrameBuffer>.broadcast();
  // StreamController.stream creates a fresh wrapper on each access. Keep the
  // identity stable so status/parent rebuilds do not reset bitmap preview.
  late final Stream<FrameBuffer> _frameStream = _frames.stream;
  final _bitmapFrames = StreamController<FrameBuffer>.broadcast();
  late final Stream<FrameBuffer> _bitmapStream = _bitmapFrames.stream;
  BitmapPreviewDemand? _bitmapDemand;
  final _samplingClock = Stopwatch();
  Duration? _lastAnalysisAt, _lastBitmapAt, _lastPreviewSampleAt, _lastReadAt;
  int _bitmapOffers = 0, _samples = 0, _sampleTotalUs = 0, _sampleMaxUs = 0;
  double _sampleEwmaUs = 0;

  Duration get _readbackInterval => Duration(
    // Approximate copy/downsample duty budget for extra preview reads. Analysis
    // may still need work sooner; this is not a bound on total app CPU.
    microseconds: math.max(
      _previewInterval.inMicroseconds,
      (_sampleEwmaUs * 5).ceil(),
    ),
  );

  @override
  BitmapPreviewMetrics? get bitmapPreviewMetrics =>
      previewMode != UvcPreviewMode.bitmap || !_streaming
      ? null
      : BitmapPreviewMetrics(
          elapsed: _samplingClock.elapsed,
          offeredFrames: _bitmapOffers,
          sampledFrames: _samples,
          totalSamplingTime: Duration(microseconds: _sampleTotalUs),
          maxSamplingTime: Duration(microseconds: _sampleMaxUs),
          requestedInterval: bitmapPreviewInterval,
          effectiveInterval: _readbackInterval,
          lastOfferedAt: _lastBitmapAt,
          previewWidth: _sampleWidth,
          previewHeight: _sampleHeight,
          loadLevel: _load,
          previewInterval: _previewInterval,
          decodeTime: _bitmapDemand?.lastDecodeTime ?? Duration.zero,
          uiFrameTime: _bitmapDemand?.lastUiFrameTime ?? Duration.zero,
        );

  bool _due(Duration now, Duration? last, Duration interval) =>
      last == null || now + const Duration(milliseconds: 5) - last >= interval;
  UvcCamera? _camera;
  Timer? _timer;
  StreamSubscription<UvcStreamError>? _errors;
  int? _texture;
  int _sequence = -1;
  Size _size = Size.zero;
  final _liveness = Stopwatch();
  @override
  double? get deliveredPreviewFps => _camera?.getStreamStats().deliveredFps;
  int get nativeSequence => _camera?.latestFrameSequence() ?? 0;
  @override
  Stream<FrameBuffer> get frames => _frameStream;
  @override
  Size get previewSize => _size;
  UvcCamera _getCamera() {
    if (_testCamera == null && !Platform.isWindows) {
      throw UnsupportedError('Windows x64 only');
    }
    return _camera ??= _testCamera ?? UvcCamera();
  }

  @override
  Future<List<CameraDevice>> listDevices() => _operations.run(_listDevices);

  Future<List<CameraDevice>> _listDevices() async {
    try {
      return (await _getCamera().listUsbDevices())
          .map((d) => CameraDevice(id: '${d.deviceId}', name: d.displayName))
          .toList();
    } finally {
      if (!_streaming) {
        final camera = _camera;
        _camera = null;
        await camera?.dispose();
      }
    }
  }

  @override
  Future<void> start({
    String? deviceId,
    ResolutionPreset preset = ResolutionPreset.high,
  }) => _operations.run(() => _start(deviceId: deviceId, preset: preset));

  Future<void> _start({
    String? deviceId,
    required ResolutionPreset preset,
  }) async {
    if (_streaming) throw StateError('Camera already started');
    final camera = _getCamera();
    camera.setLogLevel(UvcLogLevel.error);
    try {
      final devices = await camera.listUsbDevices();
      if (devices.isEmpty) {
        throw StateError(
          'Không tìm thấy camera USB. Kiểm tra kết nối và Windows Settings > Privacy & security > Camera.',
        );
      }
      final selected = deviceId == null
          ? devices.first
          : devices.firstWhere(
              (d) => '${d.deviceId}' == deviceId,
              orElse: () =>
                  throw StateError('Camera đã chọn không còn kết nối.'),
            );
      await camera.openUsbDevice(selected.deviceId);
      if (previewMode == UvcPreviewMode.texture) {
        _texture = await camera.createPreviewTexture();
        await camera.attachPreviewTexture(_texture!);
      }
      _errors = camera.streamErrors.listen((_) {
        _frames.addError(
          StateError(
            'Camera bị ngắt hoặc không đọc được frame. Hãy kết nối lại rồi thử lại.',
          ),
        );
      });
      final maxWidth = switch (preset) {
        ResolutionPreset.medium => 1280,
        ResolutionPreset.high => 1920,
        ResolutionPreset.veryHigh => 3840,
      };
      final modes =
          camera
              .supportedModes()
              .where(
                (m) =>
                    m.width <= maxWidth &&
                    m.width * m.height <= 9000000 &&
                    m.fps >= 10,
              )
              .toList()
            ..sort((a, b) {
              final area = (b.width * b.height).compareTo(a.width * a.height);
              if (area != 0) return area;
              return (a.fps - preferredNativeFps).abs().compareTo(
                (b.fps - preferredNativeFps).abs(),
              );
            });
      if (modes.isEmpty) {
        throw StateError(
          'Không có chế độ camera phù hợp với giới hạn độ phân giải/FPS.',
        );
      }
      final result = await camera.startPreviewAuto(
        candidates: modes,
        maxCandidates: 6,
      );
      if (!result.success || result.mode == null) {
        throw StateError(
          'Camera không khởi động được. Bật quyền camera trong Windows Settings hoặc liên hệ IT kiểm tra group policy.',
        );
      }
      _size = Size(
        result.mode!.width.toDouble(),
        result.mode!.height.toDouble(),
      );
      _streaming = true;
      _sequence = -1;
      _bitmapDemand = previewMode == UvcPreviewMode.bitmap
          ? BitmapPreviewDemand()
          : null;
      _samplingClock
        ..reset()
        ..start();
      _lastAnalysisAt = _lastBitmapAt = _lastPreviewSampleAt = _lastReadAt =
          null;
      _bitmapOffers = _samples = _sampleTotalUs = _sampleMaxUs = 0;
      _sampleEwmaUs = 0;
      _sampleWidth = _sampleHeight = 0;
      _liveness
        ..reset()
        ..start();
      final tick = previewMode == UvcPreviewMode.texture
          ? pollInterval
          : const Duration(milliseconds: 16);
      _timer = Timer.periodic(tick, (_) => _poll());
    } catch (_) {
      await _stop();
      rethrow;
    }
  }

  void _poll() {
    try {
      final camera = _camera;
      if (camera == null) return;
      final sequence = camera.latestFrameSequence();
      if (sequence == _sequence) {
        if (_liveness.elapsed > const Duration(seconds: 2)) {
          _timer?.cancel();
          _frames.addError(
            StateError('Camera ngừng gửi hình. Kiểm tra cáp USB và thử lại.'),
          );
        }
        return;
      }
      _liveness
        ..reset()
        ..start();
      _sequence = sequence;
      final now = _samplingClock.elapsed;
      final analysis =
          _frames.hasListener &&
          _due(now, _lastAnalysisAt, pollInterval) &&
          (_analysisWanted?.call() ?? true);
      final preview =
          _bitmapDemand?.canAcceptFrame == true &&
          _bitmapFrames.hasListener &&
          (_previewAllowed?.call() ?? true) &&
          _due(now, _lastPreviewSampleAt, _previewInterval) &&
          _due(now, _lastReadAt, _readbackInterval);
      final extraReadAllowed = _due(now, _lastReadAt, _readbackInterval);
      if (!analysis && !(preview && extraReadAllowed)) return;
      if (analysis) _lastAnalysisAt = now;
      final cost = Stopwatch()..start();
      final sampled = camera.copyLatestSampledFrames(
        analysisMaxDimension: analysis ? 640 : 0,
        previewMaxDimension: preview ? _previewMaximum : 0,
      );
      if (sampled == null) return;
      final raw = sampled.analysis ?? sampled.preview;
      if (raw == null) return;
      _sequence = raw.sequence;
      _liveness
        ..reset()
        ..start();
      cost.stop();
      final us = cost.elapsedMicroseconds;
      _lastReadAt = now;
      _bitmapDemand?.recordSamplingCost(cost.elapsed);
      _samples++;
      _sampleTotalUs += us;
      _sampleMaxUs = math.max(_sampleMaxUs, us);
      _sampleEwmaUs = _samples == 1
          ? us.toDouble()
          : _sampleEwmaUs * .875 + us * .125;
      final capturedAt = DateTime.now();
      FrameBuffer frame(UvcPreviewFrame raw) => FrameBuffer(
        width: raw.width,
        height: raw.height,
        rgba: raw.rgbaBytes,
        capturedAt: capturedAt,
        sequence: raw.sequence,
      );
      if (analysis && sampled.analysis != null) {
        _frames.add(frame(sampled.analysis!));
      }
      if (preview && sampled.preview != null) {
        // Reserve from sampling start. Copy/decode cost must not accumulate
        // in every requested period. Never catch up missed frames in a loop.
        _lastPreviewSampleAt = now;
        _lastBitmapAt = _samplingClock.elapsed;
        _sampleWidth = sampled.preview!.width;
        _sampleHeight = sampled.preview!.height;
        _bitmapOffers++;
        _bitmapFrames.add(frame(sampled.preview!));
      }
    } catch (_) {
      _timer?.cancel();
      _frames.addError(
        StateError('Không đọc được hình camera. Khởi động lại camera.'),
      );
    }
  }

  @override
  Future<FrameBuffer?> latestFullResolutionFrame() =>
      _operations.run(_snapshot);

  Future<FrameBuffer?> _snapshot() async {
    if (_liveness.elapsed > const Duration(milliseconds: 500)) return null;
    final raw = _camera?.copyLatestFrame();
    if (raw == null) return null;
    return FrameBuffer(
      width: raw.width,
      height: raw.height,
      rgba: raw.rgbaBytes,
      capturedAt: DateTime.now(),
      sequence: raw.sequence,
    );
  }

  @override
  Widget buildPreview() {
    if (!_streaming) return const SizedBox.shrink();
    if (previewMode == UvcPreviewMode.bitmap) {
      return RgbaCameraPreview(
        frames: _bitmapStream,
        frameDemand: _bitmapDemand,
        maxDimension: 1280,
        onDecodeError: (_, __) {
          if (_streaming) {
            _frames.addError(
              StateError(
                'Không hiển thị được preview bitmap. Khởi động lại camera.',
              ),
            );
          }
        },
      );
    }
    return _texture == null
        ? const SizedBox.shrink()
        : Texture(textureId: _texture!);
  }

  @override
  Future<void> stop() => _operations.run(_stop);

  Future<void> _stop() async {
    _streaming = false;
    _samplingClock.stop();
    _bitmapDemand = null;
    _timer?.cancel();
    _timer = null;
    await _errors?.cancel();
    _errors = null;
    final camera = _camera;
    _camera = null;
    final texture = _texture;
    _texture = null;
    _size = Size.zero;
    _liveness.stop();
    if (camera == null) return;
    try {
      await camera.stopPreview();
    } finally {
      try {
        if (texture != null) await camera.disposePreviewTexture(texture);
      } finally {
        await camera.dispose();
      }
    }
  }
}
