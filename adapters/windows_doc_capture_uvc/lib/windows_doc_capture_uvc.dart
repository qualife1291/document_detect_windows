import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_ffi_uvc/flutter_ffi_uvc.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';

enum UvcPreviewMode { texture, bitmap }

/// Experimental candidate. Texture is the default; bitmap is an explicit,
/// bounded low-rate fallback that does not register a Flutter external texture.
class UvcFrameSource
    implements FrameSource, FrameSourceDiagnostics, AnalysisDemandSource {
  UvcFrameSource({
    this.previewMode = UvcPreviewMode.texture,
    this.pollInterval = const Duration(milliseconds: 100),
    this.preferredNativeFps = 30,
  }) : _testCamera = null {
    _validateInterval();
  }
  @visibleForTesting
  UvcFrameSource.testing({
    required UvcCamera camera,
    this.previewMode = UvcPreviewMode.texture,
    this.pollInterval = const Duration(milliseconds: 100),
    this.preferredNativeFps = 30,
  }) : _testCamera = camera {
    _validateInterval();
  }
  final UvcPreviewMode previewMode;
  final Duration pollInterval;
  final int preferredNativeFps;
  final UvcCamera? _testCamera;
  bool _streaming = false;
  void _validateInterval() {
    if (preferredNativeFps < 10 || preferredNativeFps > 120) {
      throw ArgumentError.value(preferredNativeFps, 'preferredNativeFps');
    }
    if (pollInterval < const Duration(milliseconds: 50) ||
        pollInterval > const Duration(seconds: 1)) {
      throw ArgumentError.value(pollInterval, 'pollInterval');
    }
  }

  final _operations = CameraOperationQueue();
  bool Function()? _analysisWanted;
  @override
  set analysisWanted(bool Function()? wanted) => _analysisWanted = wanted;
  final _frames = StreamController<FrameBuffer>.broadcast();
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
  Stream<FrameBuffer> get frames => _frames.stream;
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
      _liveness
        ..reset()
        ..start();
      _timer = Timer.periodic(pollInterval, (_) => _poll());
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
      if (!(_analysisWanted?.call() ?? true)) return;
      final raw = camera.copyLatestFrame();
      if (raw == null) return;
      _sequence = raw.sequence;
      _liveness
        ..reset()
        ..start();
      // Analysis and optional bitmap preview share this bounded buffer. Native
      // Texture does not read it. Full RGBA is copied first: profile that cost.
      final width = math.max(
            2,
            (raw.width * math.min(1, 640 / math.max(raw.width, raw.height)))
                .round(),
          ),
          height = math.max(
            2,
            math.min(640, (raw.height * width / raw.width).round()),
          );
      final rgba = Uint8List(width * height * 4);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final from =
              ((y * raw.height ~/ height) * raw.width +
                  x * raw.width ~/ width) *
              4;
          final to = (y * width + x) * 4;
          rgba[to] = raw.rgbaBytes[from];
          rgba[to + 1] = raw.rgbaBytes[from + 1];
          rgba[to + 2] = raw.rgbaBytes[from + 2];
          rgba[to + 3] = 255;
        }
      }
      _frames.add(
        FrameBuffer(
          width: width,
          height: height,
          rgba: rgba,
          capturedAt: DateTime.now(),
          sequence: raw.sequence,
        ),
      );
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
        frames: _frames.stream,
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
