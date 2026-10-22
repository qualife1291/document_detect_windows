import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera_desktop/camera_desktop.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart'
    as camera;
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:windows_doc_capture/windows_doc_capture.dart';

/// Optional measurement candidate: dependencies intentionally outside root graph.
class DesktopFrameSource implements FrameSource {
  final _backend = CameraDesktopPlugin();
  final _frames = StreamController<FrameBuffer>.broadcast();
  StreamSubscription<camera.CameraImageData>? _subscription;
  StreamSubscription<camera.CameraErrorEvent>? _errors;
  int? _id;
  Size _size = Size.zero;
  int _sequence = 0;
  final _sampleClock = Stopwatch()..start();
  @override
  Stream<FrameBuffer> get frames => _frames.stream;
  @override
  Size get previewSize => _size;
  void _check() {
    if (!Platform.isWindows) throw UnsupportedError('Windows x64 only');
  }

  @override
  Future<List<CameraDevice>> listDevices() async {
    _check();
    return (await _backend.availableCameras())
        .map((d) => CameraDevice(id: d.name, name: d.name))
        .toList();
  }

  @override
  Future<void> start({
    String? deviceId,
    ResolutionPreset preset = ResolutionPreset.high,
  }) async {
    _check();
    if (_id != null) throw StateError('Camera already started');
    try {
      final devices = await _backend.availableCameras();
      if (devices.isEmpty) {
        throw StateError(
          'Không tìm thấy camera. Kiểm tra Windows Settings > Privacy & security > Camera.',
        );
      }
      final device = deviceId == null
          ? devices.first
          : devices.firstWhere((d) => d.name == deviceId);
      final resolution = switch (preset) {
        ResolutionPreset.medium => camera.ResolutionPreset.medium,
        ResolutionPreset.high => camera.ResolutionPreset.high,
        ResolutionPreset.veryHigh => camera.ResolutionPreset.veryHigh,
      };
      final id = await _backend.createCamera(
        device,
        resolution,
        enableAudio: false,
      );
      _id = id;
      final initialized = _backend.onCameraInitialized(id).first;
      _errors = _backend.onCameraError(id).listen((_) {
        _frames.addError(
          StateError('Camera gặp lỗi. Kiểm tra quyền camera và kết nối USB.'),
        );
      });
      await _backend.initializeCamera(
        id,
        imageFormatGroup: camera.ImageFormatGroup.bgra8888,
      );
      final event = await initialized.timeout(const Duration(seconds: 10));
      _size = Size(event.previewWidth, event.previewHeight);
      _sampleClock
        ..reset()
        ..start();
      _subscription = _backend
          .onStreamedFrameAvailable(id)
          .listen(
            (frame) {
              if (_sampleClock.elapsedMilliseconds < 100) return;
              _sampleClock.reset();
              if (frame.format.group != camera.ImageFormatGroup.bgra8888 ||
                  frame.planes.isEmpty) {
                _frames.addError(
                  StateError('Camera backend must provide BGRA8888'),
                );
                return;
              }
              final p = frame.planes.first,
                  w = math.min(640, frame.width),
                  h = math.max(2, (frame.height * w / frame.width).round());
              final bytes = Uint8List(w * h * 4);
              for (var y = 0; y < h; y++) {
                for (var x = 0; x < w; x++) {
                  final s =
                          (y * frame.height ~/ h) * p.bytesPerRow +
                          (x * frame.width ~/ w) * 4,
                      d = (y * w + x) * 4;
                  bytes[d] = p.bytes[s + 2];
                  bytes[d + 1] = p.bytes[s + 1];
                  bytes[d + 2] = p.bytes[s];
                  bytes[d + 3] = 255;
                }
              }
              _frames.add(
                FrameBuffer(
                  width: w,
                  height: h,
                  rgba: bytes,
                  capturedAt: DateTime.now(),
                  sequence: ++_sequence,
                ),
              );
            },
            onError: (Object _) {
              _frames.addError(StateError('Camera frame stream failed'));
            },
          );
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  @override
  Future<FrameBuffer?> latestFullResolutionFrame() async {
    final id = _id;
    if (id == null) return null;
    final file = await _backend.takePicture(id);
    try {
      // Native backend writes a temporary full-resolution image. Delete it
      // immediately; operator-managed saveDirectory applies only to outputs.
      final encoded = TransferableTypedData.fromList([
        await file.readAsBytes(),
      ]);
      final timestamp = DateTime.now(), sequence = ++_sequence;
      return await Isolate.run(() {
        final decoded = img.decodeImage(encoded.materialize().asUint8List());
        if (decoded == null) return null;
        return FrameBuffer(
          width: decoded.width,
          height: decoded.height,
          rgba: decoded.getBytes(order: img.ChannelOrder.rgba),
          capturedAt: timestamp,
          sequence: sequence,
        );
      });
    } finally {
      await File(file.path).delete();
    }
  }

  @override
  Widget buildPreview() {
    final id = _id;
    if (id == null) return const SizedBox.shrink();
    // camera_desktop mirrors its Windows Texture widget; undo that transform
    // so analysis coordinates and preview share an unmirrored coordinate space.
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(-1, 1, 1),
      child: _backend.buildPreview(id),
    );
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _errors?.cancel();
    _errors = null;
    final id = _id;
    _id = null;
    _size = Size.zero;
    if (id != null) await _backend.dispose(id);
  }
}
