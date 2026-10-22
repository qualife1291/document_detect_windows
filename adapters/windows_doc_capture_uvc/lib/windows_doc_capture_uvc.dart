import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_ffi_uvc/flutter_ffi_uvc.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';

/// Experimental candidate, not a measured default. Preview stays in Texture.
class UvcFrameSource implements FrameSource, FrameSourceDiagnostics {
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
    if (!Platform.isWindows) throw UnsupportedError('Windows x64 only');
    return _camera ??= UvcCamera();
  }

  @override
  Future<List<CameraDevice>> listDevices() async {
    try {
      return (await _getCamera().listUsbDevices())
          .map((d) => CameraDevice(id: '${d.deviceId}', name: d.displayName))
          .toList();
    } finally {
      if (_texture == null) {
        await _camera?.dispose();
        _camera = null;
      }
    }
  }

  @override
  Future<void> start({
    String? deviceId,
    ResolutionPreset preset = ResolutionPreset.high,
  }) async {
    if (_texture != null) throw StateError('Camera already started');
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
      _texture = await camera.createPreviewTexture();
      await camera.attachPreviewTexture(_texture!);
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
              .where((m) => m.width <= maxWidth && m.fps >= 10)
              .toList()
            ..sort(
              (a, b) => (b.width * b.height).compareTo(a.width * a.height),
            );
      final result = await camera.startPreviewAuto(
        candidates: modes.isEmpty ? null : modes,
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
      _sequence = -1;
      _liveness
        ..reset()
        ..start();
      _timer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _poll(),
      );
    } catch (_) {
      await stop();
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
      final raw = camera.copyLatestFrame();
      if (raw == null) return;
      _sequence = raw.sequence;
      _liveness
        ..reset()
        ..start();
      // Analysis only. Native Texture never reads this Dart buffer. This
      // backend copies full RGBA before this downsample: profile that cost.
      final width = math.min(640, raw.width),
          height = math.max(2, (raw.height * width / raw.width).round());
      final rgba = Uint8List(width * height * 4);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final from =
              ((y * raw.height ~/ height) * raw.width +
                  x * raw.width ~/ width) *
              4;
          final to = (y * width + x) * 4;
          rgba.setRange(to, to + 4, raw.rgbaBytes, from);
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
  Future<FrameBuffer?> latestFullResolutionFrame() async {
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
  Widget buildPreview() => _texture == null
      ? const SizedBox.shrink()
      : Texture(textureId: _texture!);
  @override
  Future<void> stop() async {
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
