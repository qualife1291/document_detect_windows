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
class DesktopFrameSource implements FrameSource, AnalysisDemandSource {
  final _backend = CameraDesktopPlugin();
  final _operations = CameraOperationQueue();
  bool Function()? _analysisWanted;
  @override
  set analysisWanted(bool Function()? wanted) => _analysisWanted = wanted;
  final _frames = StreamController<FrameBuffer>.broadcast();
  StreamSubscription<camera.CameraImageData>? _subscription;
  StreamSubscription<camera.CameraErrorEvent>? _errors;
  int? _id;
  Size _size = Size.zero;
  int _sequence = 0;
  final _sampleClock = Stopwatch()..start();
  final _deliveryClock = Stopwatch();
  Timer? _watchdog;

  void _streamFailure(String message) {
    _watchdog?.cancel();
    if (_id != null) _frames.addError(StateError(message));
  }

  @override
  Stream<FrameBuffer> get frames => _frames.stream;
  @override
  Size get previewSize => _size;
  void _check() {
    if (!Platform.isWindows) throw UnsupportedError('Windows x64 only');
  }

  @override
  Future<List<CameraDevice>> listDevices() => _operations.run(_listDevices);

  Future<List<CameraDevice>> _listDevices() async {
    _check();
    return (await _backend.availableCameras())
        .map((d) => CameraDevice(id: d.name, name: d.name))
        .toList();
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
      final initialized = Completer<camera.CameraInitializedEvent>();
      final initialization = _backend
          .onCameraInitialized(id)
          .listen(
            (event) {
              if (!initialized.isCompleted) initialized.complete(event);
            },
            onError: (Object error, StackTrace stack) {
              if (!initialized.isCompleted) {
                initialized.completeError(error, stack);
              }
            },
          );
      unawaited(
        initialized.future.then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {},
        ),
      );
      _errors = _backend.onCameraError(id).listen((_) {
        _frames.addError(
          StateError('Camera gặp lỗi. Kiểm tra quyền camera và kết nối USB.'),
        );
      });
      late camera.CameraInitializedEvent event;
      try {
        await _backend
            .initializeCamera(
              id,
              imageFormatGroup: camera.ImageFormatGroup.bgra8888,
            )
            .timeout(const Duration(seconds: 10));
        event = await initialized.future.timeout(const Duration(seconds: 10));
      } finally {
        await initialization.cancel();
      }
      _size = Size(event.previewWidth, event.previewHeight);
      _sampleClock
        ..reset()
        ..start();
      _subscription = _backend
          .onStreamedFrameAvailable(id)
          .listen(
            (frame) {
              _deliveryClock
                ..reset()
                ..start();
              if (_sampleClock.elapsedMilliseconds < 100 ||
                  !(_analysisWanted?.call() ?? true)) {
                return;
              }
              _sampleClock.reset();
              if (frame.format.group != camera.ImageFormatGroup.bgra8888 ||
                  frame.planes.isEmpty) {
                _frames.addError(
                  StateError('Camera backend must provide BGRA8888'),
                );
                return;
              }
              final p = frame.planes.first;
              if (frame.width < 2 ||
                  frame.height < 2 ||
                  frame.width * frame.height > 33554432 ||
                  p.bytesPerRow < frame.width * 4 ||
                  p.bytes.length <
                      (frame.height - 1) * p.bytesPerRow + frame.width * 4) {
                _frames.addError(
                  StateError('Invalid BGRA frame dimensions or stride'),
                );
                return;
              }
              final w = math.max(
                    2,
                    (frame.width *
                            math.min(
                              1,
                              640 / math.max(frame.width, frame.height),
                            ))
                        .round(),
                  ),
                  h = math.max(
                    2,
                    math.min(640, (frame.height * w / frame.width).round()),
                  );
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
              _streamFailure('Camera frame stream failed');
            },
            onDone: () => _streamFailure('Camera frame stream closed'),
          );
      _deliveryClock
        ..reset()
        ..start();
      _watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_deliveryClock.elapsed > const Duration(seconds: 2)) {
          _streamFailure(
            'Camera stopped delivering frames. Reconnect and restart.',
          );
        }
      });
    } catch (_) {
      await _stop();
      rethrow;
    }
  }

  @override
  Future<FrameBuffer?> latestFullResolutionFrame() async {
    // Serialize only the native request. Decode owns bytes/file and can finish
    // independently while stop releases the camera.
    final file = await _operations.run(() async {
      final id = _id;
      if (id == null) return null;
      var abandoned = false;
      final request = _backend.takePicture(id);
      unawaited(
        request
            .then<void>((lateFile) async {
              if (abandoned) await File(lateFile.path).delete();
            })
            .catchError((Object _) {}),
      );
      try {
        return await request.timeout(const Duration(seconds: 10));
      } catch (_) {
        abandoned = true;
        rethrow;
      }
    });
    if (file == null) return null;
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
  Future<void> stop() => _operations.run(_stop);

  Future<void> _stop() async {
    _watchdog?.cancel();
    _watchdog = null;
    _deliveryClock.stop();
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
