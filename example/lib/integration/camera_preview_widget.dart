import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'package:windows_doc_capture_uvc/windows_doc_capture_uvc.dart';

enum DocumentCameraCaptureMode { single, batch }

typedef OnCaptureCallback = ValueChanged<Uint8List>;

typedef CameraHardwareRelease = Future<void> Function();
typedef CameraHardwareAcquire = Future<CameraHardwareRelease> Function();
typedef DocumentCameraSelector = CameraDevice Function(List<CameraDevice>);

/// One controller per preview. The host owns received JPEG bytes and callbacks.
class CameraPreviewController {
  _CameraPreviewWidgetState? _view;
  Future<void> _released = Future<void>.value();
  ValueChanged<Uint8List>? onCaptured;
  bool get isAttached => _view != null;
  bool get isReady => _view?._canCapture ?? false;

  Future<void> capture() {
    final view = _view;
    if (view == null) throw StateError('Camera preview is not mounted');
    return view._takePicture();
  }

  /// Resume/retake explicitly after a route becomes visible again.
  Future<void> resume() {
    final view = _view;
    if (view == null) throw StateError('Camera preview is not mounted');
    return view._resume();
  }

  /// Await this BEFORE navigation/handoff to another camera feature.
  Future<void> stop() => _view?._stop() ?? _released;

  /// Terminal for the current view. stop() is the reusable route pause.
  Future<void> shutdown() => _view?._shutdown() ?? _released;
}

/// Copyable kiosk integration sample, Windows x64 / UVC only.
///
/// active must track host route/tab visibility; app lifecycle cannot infer it.
/// No fixed ROI, digital zoom, mirroring, temporary images or file export.
class CameraPreviewWidget extends StatefulWidget {
  const CameraPreviewWidget({
    super.key,
    this.controller,
    this.onCaptured,
    this.onDocumentStateChanged,
    this.selectCamera,
    this.acquireHardware,
    this.configureCamera,
    this.active = true,
    this.autoStart = true,
    this.enableAutoCapture = false,
    this.captureMode = DocumentCameraCaptureMode.batch,
    this.preset = ResolutionPreset.high,
    this.cornerRadius = 6,
    this.validColor = const Color(0xff69f0ae),
    this.warningColor = Colors.white,
    this.captureFactory,
  });

  final CameraPreviewController? controller;

  /// Takes precedence over controller.onCaptured; choose one delivery callback.
  final ValueChanged<Uint8List>? onCaptured;
  final ValueChanged<DocumentPreviewState>? onDocumentStateChanged;

  /// Required if multiple devices exist. No fallback to a different camera.
  final DocumentCameraSelector? selectCamera;

  /// Returns cleanup that turns off lights/releases the host hardware lease.
  final CameraHardwareAcquire? acquireHardware;

  /// Optional verified UVC-compatible controls; never open a second camera here.
  final Future<void> Function(CameraDevice)? configureCamera;
  final bool active, autoStart, enableAutoCapture;

  /// single: stop/release before callback; batch: keep one session and auto latch.
  final DocumentCameraCaptureMode captureMode;
  final ResolutionPreset preset;
  final double cornerRadius;
  final Color validColor, warningColor;

  /// Dependency injection for tests/custom budgets; called once per mounted view.
  final WindowsDocCapture Function()? captureFactory;

  @override
  State<CameraPreviewWidget> createState() => _CameraPreviewWidgetState();
}

class _CameraPreviewWidgetState extends State<CameraPreviewWidget> {
  late final WindowsDocCapture _capture;
  late final CameraPreviewController _controller;
  Future<void>? _previousRelease;
  final _operations = CameraOperationQueue();
  CameraHardwareRelease? _release;
  StreamSubscription<Object>? _errors;
  AppLifecycleListener? _lifecycle;
  Future<void>? _starting, _stopping, _closing;
  bool _wanted = false, _closed = false, _ready = false;
  bool _taking = false, _delivering = false, _captured = false;
  int _epoch = 0;
  String? _error, _notice;

  bool get _canCapture =>
      _ready &&
      _wanted &&
      !_taking &&
      !_delivering &&
      !_closed &&
      _foreground &&
      _capture.currentPreviewStatus.state != DocumentPreviewState.capturing;

  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached;
  }

  bool _current(int epoch) =>
      mounted && !_closed && _wanted && _foreground && epoch == _epoch;

  void _refresh() {
    if (mounted && !_closed) setState(() {});
  }

  void _log(String event, [Object? error]) {
    if (!_capture.enableDebugLogging) return;
    try {
      debugPrint(
        '[kiosk_document_camera] ${jsonEncode({'v': 1, 'event': event, if (error != null) 'errorType': error.runtimeType.toString()})}',
      );
    } catch (_) {
      // Diagnostic sinks must not interrupt camera/hardware cleanup.
    }
  }

  void _observe(Future<void> operation) {
    unawaited(
      operation.catchError((Object error) async {
        _log('operation_error', error);
        _error =
            'Không mở hoặc đóng được camera. Kiểm tra thiết bị rồi thử lại.';
        if (!_closed) {
          try {
            await _stop();
          } catch (cleanupError) {
            _log('cleanup_error', cleanupError);
          }
        }
        _refresh();
      }),
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? CameraPreviewController();
    _capture =
        widget.captureFactory?.call() ??
        WindowsDocCapture(
          analysisInterval: const Duration(milliseconds: 200),
          cropPipeline: const CropPipeline(jpegQuality: 92),
          frameSource: UvcFrameSource(
            previewMode: UvcPreviewMode.bitmap,
            bitmapPreviewProfile: BitmapPreviewProfile.balanced,
            pollInterval: const Duration(milliseconds: 200),
            preferredNativeFps: 15,
          ),
        );
    _previousRelease = _controller._released;
    if (_controller._view != null) {
      throw StateError('Mount only one preview per CameraPreviewController');
    }
    _controller._view = this;
    _errors = _capture.errors.listen((error) {
      _log('camera_error', error);
      _error =
          'Camera gặp lỗi hoặc ngắt kết nối. Kiểm tra thiết bị rồi thử lại.';
      _observe(_stop());
    });
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (!_foreground) _observe(_stop());
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active && widget.autoStart && _foreground) {
        _observe(_resume());
      }
    });
  }

  @override
  void didUpdateWidget(CameraPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      throw StateError('Keep the controller stable for this mounted preview');
    }
    if (oldWidget.active != widget.active) {
      _observe(widget.active ? _resume() : _stop());
    }
    if (_ready && oldWidget.enableAutoCapture != widget.enableAutoCapture) {
      _capture.autoCaptureEnabled = widget.enableAutoCapture;
    }
  }

  Future<void> _resume() {
    if (_closed) return Future<void>.error(StateError('Preview shut down'));
    if (!_foreground || !widget.active) return Future<void>.value();
    if (_wanted) return _starting ?? Future<void>.value();
    _wanted = true;
    _captured = false;
    _error = _notice = null;
    final epoch = ++_epoch;
    final future = _operations.run(() async {
      try {
        final previousRelease = _previousRelease;
        if (previousRelease != null) {
          await previousRelease;
          _previousRelease = null;
        }
        if (!_current(epoch)) return;
        if (widget.acquireHardware != null) {
          _release = await widget.acquireHardware!();
        }
        if (!_current(epoch)) return;
        final devices = await _capture.listDevices();
        if (!_current(epoch)) return;
        if (devices.isEmpty) throw StateError('No document camera');
        final selected = widget.selectCamera != null
            ? widget.selectCamera!(List.unmodifiable(devices))
            : devices.length == 1
            ? devices.single
            : throw StateError('Select the document camera explicitly');
        if (!devices.any((d) => d.id == selected.id)) {
          throw StateError('Selected camera is unavailable');
        }
        await _capture.start(
          deviceId: selected.id,
          preset: widget.preset,
          enableAutoCapture: false,
          // No saveDirectory: both JPEGs stay in memory.
          onAutoCapture: (document) => _observe(_deliver(document, epoch)),
          onDocumentStateChanged: (state) {
            if (_current(epoch)) widget.onDocumentStateChanged?.call(state);
          },
        );
        if (!_current(epoch)) return;
        await widget.configureCamera?.call(selected);
        if (!_current(epoch)) return;
        _ready = true;
        _capture.autoCaptureEnabled = widget.enableAutoCapture;
        _log('ready');
      } catch (error) {
        if (_current(epoch)) {
          _wanted = false;
          _error =
              'Không mở được camera giấy tờ. Kiểm tra cấu hình camera và quyền Windows.';
          rethrow;
        }
      } finally {
        if (!_current(epoch) || !_ready) await _stopHardware();
      }
    });
    _starting = future;
    _refresh();
    return future.whenComplete(() {
      if (identical(_starting, future)) _starting = null;
      _refresh();
    });
  }

  Future<void> _stopHardware() async {
    _ready = false;
    Object? failure;
    StackTrace? failureStack;
    try {
      await _capture.stop();
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    }
    final release = _release;
    _release = null;
    try {
      if (release != null) await release();
    } catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
    _log('stopped');
  }

  Future<void> _stop() {
    _wanted = false;
    ++_epoch;
    _ready = false;
    _refresh();
    if (_stopping != null) return _stopping!;
    // Cancel root startup/snapshot/worker immediately, before queued host work.
    final cancellation = _capture.stop();
    unawaited(
      cancellation.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    final future = _operations.run(() async {
      try {
        await cancellation;
      } finally {
        await _stopHardware();
      }
    });
    _stopping = future;
    return future.whenComplete(() {
      if (identical(_stopping, future)) _stopping = null;
      _refresh();
    });
  }

  Future<void> _takePicture() async {
    if (!_canCapture) {
      throw StateError('Camera is not ready or capture is busy');
    }
    final epoch = _epoch;
    _taking = true;
    _notice = null;
    _refresh();
    try {
      final document = await _capture.captureNow();
      if (!_current(epoch)) return;
      if (document == null) {
        _notice =
            'Chưa thấy đủ bốn góc giấy tờ. Đưa giấy vào khung rồi thử lại.';
        return;
      }
      await _deliver(document, epoch);
    } finally {
      _taking = false;
      _refresh();
    }
  }

  Future<void> _deliver(CapturedDocument document, int epoch) async {
    if (!_current(epoch) || _delivering) return;
    _delivering = true;
    final single = widget.captureMode == DocumentCameraCaptureMode.single;
    if (single) {
      _ready = false;
      _capture.autoCaptureEnabled = false;
    }
    _refresh();
    try {
      // Single-photo host callbacks may immediately open review/OCR/navigation.
      // Batch callers append bytes and keep this session; stop before dialogs.
      if (single) await _operations.run(_stopHardware);
      if (!_current(epoch)) return;
      if (single) {
        _wanted = false;
        _captured = true;
      }
      final callback = widget.onCaptured ?? _controller.onCaptured;
      callback?.call(document.croppedJpeg);
      _log('delivered');
    } finally {
      _delivering = false;
      _refresh();
    }
  }

  Future<void> _shutdown() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    try {
      await _stop();
    } finally {
      try {
        await _errors?.cancel();
      } finally {
        await _capture.dispose();
      }
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    final closing = _shutdown();
    if (identical(_controller._view, this)) {
      _controller._view = null;
      _controller._released = closing;
    }
    _observe(closing);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            TextButton(
              onPressed: _starting != null || _stopping != null
                  ? null
                  : () {
                      _observe(_resume());
                    },
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    if (!_ready) {
      return Center(
        child: Text(
          _captured
              ? 'Đã chụp giấy tờ'
              : _taking || _delivering
              ? 'Đang xử lý ảnh…'
              : _starting != null || _stopping != null
              ? 'Đang chuẩn bị camera…'
              : 'Camera đang tạm dừng',
        ),
      );
    }
    return Stack(
      fit: StackFit.loose,
      children: [
        _capture.buildPreview(
          fit: BoxFit.contain,
          frameStyle: DocumentFrameStyle.outline,
          cornerRadius: widget.cornerRadius,
          warningColor: widget.warningColor,
          validColor: widget.validColor,
        ),
        if (_notice != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: ColoredBox(
              color: Colors.black87,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _notice!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
