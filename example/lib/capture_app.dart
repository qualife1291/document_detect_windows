import 'dart:async';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';

class CaptureApp extends StatelessWidget {
  const CaptureApp({super.key, required this.capture});
  final WindowsDocCapture capture;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chụp giấy tờ',
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xff101820),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xff90caf9),
        surface: Color(0xff101820),
      ),
      focusColor: Colors.white38,
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? const BorderSide(color: Colors.white, width: 3)
                : BorderSide.none,
          ),
        ),
      ),
    ),
    home: CapturePage(capture: capture),
  );
}

class CapturePage extends StatefulWidget {
  const CapturePage({super.key, required this.capture});
  final WindowsDocCapture capture;
  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  WindowsDocCapture get capture => widget.capture;
  StreamSubscription<CaptureStatus>? _statusSub;
  StreamSubscription<Object>? _errorSub;
  CaptureStatus? _status;
  DocumentPreviewState _documentState = DocumentPreviewState.idle;
  CapturedDocument? _result;
  List<CameraDevice> _devices = [];
  String? _device, _error;
  bool _busy = false,
      _auto = true,
      _debug = false,
      _started = false,
      _save = false;
  AppLifecycleListener? _lifecycle;
  final _saveDirectory = TextEditingController();
  final _captureFocus = FocusNode();
  final _resultFocus = FocusNode();
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        try {
          await capture.dispose();
        } catch (_) {
          /* Native cleanup attempted. */
        }
        return AppExitResponse.exit;
      },
    );
    _statusSub = capture.statuses.listen((status) {
      if (mounted) setState(() => _status = status);
    });
    _errorSub = capture.errors.listen((_) {
      if (mounted) {
        setState(() {
          _error =
              'Camera gặp lỗi hoặc đã ngắt kết nối. Kiểm tra cáp USB, quyền camera trong Windows Settings và thử lại.';
          _started = false;
        });
      }
    });
    unawaited(_loadDevices());
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await capture.listDevices();
      if (mounted) {
        setState(() {
          _devices = devices;
          _device = devices.isEmpty ? null : devices.first.id;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Không đọc được danh sách camera. Chỉ hỗ trợ Windows x64. Kiểm tra kết nối USB và quyền camera trong Windows Settings.',
        );
      }
    }
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_save && _saveDirectory.text.trim().isEmpty) {
        throw StateError('Missing output directory');
      }
      await capture.stop();
      await capture.start(
        deviceId: _device,
        enableAutoCapture: _auto,
        saveDirectory: _save ? _saveDirectory.text.trim() : null,
        onAutoCapture: _showResult,
        onDocumentStateChanged: (state) {
          if (mounted) {
            setState(() {
              _documentState = state;
              if (state == DocumentPreviewState.processing ||
                  state == DocumentPreviewState.idle ||
                  state == DocumentPreviewState.error) {
                _status = null;
              }
            });
          }
        },
      );
      if (mounted) setState(() => _started = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Không mở được camera. Kiểm tra camera USB, bật Settings > Privacy & security > Camera và quyền cho desktop apps; kiểm tra thư mục lưu hoặc liên hệ IT về group policy.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showResult(CapturedDocument result) {
    capture.autoCaptureEnabled = false;
    if (mounted) {
      setState(() => _result = result);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _result != null) _resultFocus.requestFocus();
      });
    }
  }

  Future<void> _manual() async {
    setState(() => _busy = true);
    try {
      final result = await capture.captureNow();
      if (result != null) {
        _showResult(result);
      } else if (mounted) {
        setState(
          () => _error =
              'Chưa thấy đủ bốn góc giấy tờ. Đưa giấy tờ vào khung rồi thử lại.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Không lưu được ảnh. Kiểm tra quyền ghi thư mục và thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _retake() {
    setState(() {
      _result = null;
      _error = null;
    });
    capture.autoCaptureEnabled = _auto;
    _captureFocus.requestFocus();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    unawaited(_statusSub?.cancel());
    unawaited(_errorSub?.cancel());
    unawaited(
      capture.dispose().catchError((Object _) {
        // Widget is already gone. Native cleanup was attempted; never setState.
      }),
    );
    _saveDirectory.dispose();
    _captureFocus.dispose();
    _resultFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final qualityWarning = status == null
        ? 'Đưa giấy tờ vào khung'
        : status.warnings.isEmpty
        ? status.state == AutoCaptureState.cooldown
              ? 'Đã chụp. Bỏ giấy ra trước lần tiếp theo.'
              : _auto
              ? 'Giữ yên — đang chuẩn bị chụp'
              : 'Sẵn sàng chụp'
        : status.warnings.map((w) => w.message).join(' • ');
    final warning = switch (_documentState) {
      DocumentPreviewState.processing => 'Đang xử lý giấy tờ…',
      DocumentPreviewState.capturing => 'Đang chụp và xử lý ảnh…',
      DocumentPreviewState.error => 'Camera gặp lỗi, hãy thử lại',
      _ => qualityWarning,
    };
    final feedback =
        _auto &&
        _documentState == DocumentPreviewState.clear &&
        status?.state == AutoCaptureState.stable;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _RetakeIntent(),
      },
      child: Actions(
        actions: {
          _RetakeIntent: CallbackAction<_RetakeIntent>(
            onInvoke: (_) {
              if (_result != null) _retake();
              return null;
            },
          ),
        },
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Material(
                  color: const Color(0xff101820),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Chụp giấy tờ',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _started
                              ? 'Camera đang hoạt động'
                              : 'Camera chưa khởi động',
                        ),
                        DropdownButton<String>(
                          value: _device,
                          hint: const Text('Chọn camera'),
                          items: _devices
                              .map(
                                (d) => DropdownMenuItem(
                                  value: d.id,
                                  child: Text(d.name),
                                ),
                              )
                              .toList(),
                          onChanged: _busy || _started
                              ? null
                              : (v) => setState(() => _device = v),
                        ),
                        FilledButton(
                          onPressed: _busy ? null : _start,
                          child: Text(_started ? 'Khởi động lại' : 'Bắt đầu'),
                        ),
                        if (!_started)
                          IconButton(
                            onPressed: _busy ? null : _loadDevices,
                            tooltip: 'Tìm lại camera',
                            icon: const Icon(Icons.refresh),
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: _auto,
                              onChanged: _result != null
                                  ? null
                                  : (v) {
                                      setState(() => _auto = v);
                                      capture.autoCaptureEnabled = v;
                                    },
                            ),
                            const Text('Tự chụp'),
                          ],
                        ),
                        IconButton(
                          onPressed: () => setState(() => _debug = !_debug),
                          icon: const Icon(Icons.speed),
                          tooltip: 'Bật/tắt chỉ số phát triển',
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_started)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _save,
                              onChanged: (v) =>
                                  setState(() => _save = v ?? false),
                            ),
                            const Text('Lưu ảnh vào thư mục'),
                          ],
                        ),
                        if (_save)
                          SizedBox(
                            width: 400,
                            child: TextField(
                              controller: _saveDirectory,
                              decoration: const InputDecoration(
                                labelText: 'Thư mục lưu do người vận hành chọn',
                              ),
                            ),
                          ),
                        const Text(
                          'Backend UVC thử nghiệm — chưa có kết quả đo Windows.',
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = capture.previewSize;
                      return Center(
                        child: AspectRatio(
                          aspectRatio: size.width > 0
                              ? size.aspectRatio
                              : 16 / 9,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const ColoredBox(color: Colors.black),
                              if (_started) capture.buildPreview(),
                              Align(
                                alignment: Alignment.topCenter,
                                child: Container(
                                  margin: const EdgeInsets.all(20),
                                  padding: const EdgeInsets.all(12),
                                  color: const Color(0xff101820),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          feedback
                                              ? Icons.hourglass_top
                                              : Icons.info_outline,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            warning,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (feedback)
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          'Chuẩn bị chụp — giữ yên',
                                          style: TextStyle(
                                            color: Colors.white,
                                            backgroundColor: Color(0xff101820),
                                          ),
                                        ),
                                        if (!reduceMotion)
                                          LinearProgressIndicator(
                                            value: status!.feedbackProgress,
                                            semanticsLabel: 'Đang giữ ổn định',
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_error != null)
                  Container(
                    width: double.infinity,
                    color: const Color(0xff512000),
                    padding: const EdgeInsets.all(12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                if (_debug && status != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Detection ${status.detectionFps.toStringAsFixed(1)} FPS · phân tích ${status.report.analysisTime.inMilliseconds} ms · preview (native delivered): ${capture.deliveredPreviewFps?.toStringAsFixed(1) ?? 'chưa đo'} FPS · camera→texture latency: chưa có timestamp native',
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 20,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        focusNode: _captureFocus,
                        onPressed: !_started || _busy || _result != null
                            ? null
                            : _manual,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Chụp ngay'),
                      ),
                      const Text(
                        'Xanh: đủ chất lượng · Cam: xem cảnh báo. Hướng dẫn: README.md',
                      ),
                    ],
                  ),
                ),
                if (_result != null)
                  Expanded(
                    child: Focus(
                      focusNode: _resultFocus,
                      autofocus: true,
                      child: Semantics(
                        label: 'Kết quả chụp giấy tờ',
                        scopesRoute: true,
                        explicitChildNodes: true,
                        child: Column(
                          children: [
                            const Text(
                              'Đã chụp giấy tờ',
                              style: TextStyle(fontSize: 22),
                            ),
                            Expanded(
                              child: Image.memory(
                                _result!.croppedJpeg,
                                semanticLabel:
                                    'Ảnh giấy tờ đã cắt và chỉnh phối cảnh',
                              ),
                            ),
                            Text(
                              _result!.savedPath == null
                                  ? 'Ảnh đang ở bộ nhớ'
                                  : 'Đã lưu ảnh vào thư mục được chọn',
                            ),
                            FilledButton(
                              onPressed: _retake,
                              child: const Text('Chụp lại (Esc)'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RetakeIntent extends Intent {
  const _RetakeIntent();
}
