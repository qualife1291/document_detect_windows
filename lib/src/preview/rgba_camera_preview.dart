import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'bitmap_preview_budget.dart';
import '../camera/frame_source.dart';

/// One bitmap consumer's readiness. Create a new handle for each camera session.
/// Sources read this before costly native readback; only the widget mutates it.
class BitmapPreviewDemand {
  bool _ready = false;
  bool get canAcceptFrame => _ready;
  final _clock = Stopwatch()..start();
  final _budget = BitmapPreviewBudget();
  int get loadLevel => _budget.level;
  Duration _lastDecode = Duration.zero, _lastUi = Duration.zero;
  Duration get lastDecodeTime => _lastDecode;
  Duration get lastUiFrameTime => _lastUi;

  /// Backends report only work they actually performed; no frame is retained.
  void recordSamplingCost(Duration cost) =>
      _budget.observe(_clock.elapsed, sampling: cost);
  void _decoded(Duration cost) {
    _lastDecode = cost;
    _budget.observe(_clock.elapsed, decode: cost);
  }

  void _timed(Duration cost) {
    _lastUi = cost;
    _budget.observe(_clock.elapsed, ui: cost);
  }
}

/// Explicit low-rate bitmap fallback for external-texture/driver problems.
/// At most one frame is decoding and one image is displayed. Busy frames are
/// dropped; this widget never buffers a history or uses Flutter's image cache.
class RgbaCameraPreview extends StatefulWidget {
  const RgbaCameraPreview({
    super.key,
    required this.frames,
    this.onDecodeError,
    this.frameDemand,
    this.maxDimension = 640,
  }) : decodeFrame = null,
       assert(maxDimension >= 2 && maxDimension <= 1920);

  @visibleForTesting
  const RgbaCameraPreview.testing({
    super.key,
    required this.frames,
    required this.decodeFrame,
    this.onDecodeError,
    this.frameDemand,
    this.maxDimension = 640,
  }) : assert(maxDimension >= 2 && maxDimension <= 1920);

  final Stream<FrameBuffer> frames;
  final BitmapPreviewDemand? frameDemand;
  final int maxDimension;
  final void Function(Object, StackTrace)? onDecodeError;
  final Future<ui.Image> Function(FrameBuffer)? decodeFrame;
  @override
  State<RgbaCameraPreview> createState() => _RgbaCameraPreviewState();
}

class _RgbaCameraPreviewState extends State<RgbaCameraPreview>
    with WidgetsBindingObserver {
  StreamSubscription<FrameBuffer>? _subscription;
  ui.Image? _image;
  bool _decoding = false;
  int _epoch = 0;
  bool _tickerEnabled = true, _active = true, _timingRegistered = false;
  bool get _visible => _tickerEnabled && _active;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _active = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _listen();
    _updateDemand();
  }

  void _updateDemand() {
    widget.frameDemand?._ready = mounted && _visible && !_decoding;
    final timingWanted = mounted && _visible && widget.frameDemand != null;
    if (timingWanted != _timingRegistered) {
      _timingRegistered = timingWanted;
      if (timingWanted) {
        SchedulerBinding.instance.addTimingsCallback(_timings);
      } else {
        SchedulerBinding.instance.removeTimingsCallback(_timings);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // SDK floor 3.32.8 predates TickerMode.valuesOf. Keep this one call until
    // the supported SDK floor exposes the replacement.
    // ignore: deprecated_member_use
    _tickerEnabled = TickerMode.of(context);
    _updateDemand();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _updateDemand();
  }

  void _timings(List<FrameTiming> timings) {
    if (!_visible || !mounted) return;
    for (final timing in timings) {
      widget.frameDemand?._timed(
        timing.buildDuration > timing.rasterDuration
            ? timing.buildDuration
            : timing.rasterDuration,
      );
    }
  }

  void _listen() {
    _subscription = widget.frames.listen(
      _frame,
      onError: (Object error, StackTrace stack) {
        // Source errors are handled by the capture controller. Forwarding them
        // into the same source from here would create an error feedback loop.
      },
    );
  }

  @override
  void didUpdateWidget(RgbaCameraPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.frameDemand, widget.frameDemand)) {
      oldWidget.frameDemand?._ready = false;
    }
    if (!identical(oldWidget.frames, widget.frames) ||
        !identical(oldWidget.frameDemand, widget.frameDemand)) {
      ++_epoch;
      unawaited(_subscription?.cancel());
      _image?.dispose();
      _image = null;
      _listen();
    }
    _updateDemand();
  }

  void _frame(FrameBuffer frame) {
    if (_decoding ||
        !_visible ||
        !mounted ||
        frame.width > widget.maxDimension ||
        frame.height > widget.maxDimension) {
      return;
    }
    _decoding = true;
    _updateDemand();
    final epoch = _epoch;
    unawaited(_decode(frame, epoch, widget.frameDemand));
  }

  Future<void> _decode(
    FrameBuffer frame,
    int epoch,
    BitmapPreviewDemand? demand,
  ) async {
    final cost = Stopwatch()..start();
    try {
      final image = await (widget.decodeFrame ?? _decodeRgba)(frame);
      if (!mounted || epoch != _epoch) {
        image.dispose();
        return;
      }
      final old = _image;
      setState(() => _image = image);
      // RawImage's render object owns a clone until it repaints/unmounts. Do not
      // queue disposal behind a GPU frame that might never be presented.
      old?.dispose();
    } catch (error, stack) {
      if (mounted && epoch == _epoch) widget.onDecodeError?.call(error, stack);
    } finally {
      if (mounted && epoch == _epoch && identical(demand, widget.frameDemand)) {
        demand?._decoded(cost.elapsed);
      }
      _decoding = false;
      if (mounted) _updateDemand();
    }
  }

  @override
  void dispose() {
    ++_epoch;
    WidgetsBinding.instance.removeObserver(this);
    if (_timingRegistered) {
      SchedulerBinding.instance.removeTimingsCallback(_timings);
    }
    widget.frameDemand?._ready = false;
    unawaited(_subscription?.cancel());
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawImage(
    image: _image,
    fit: BoxFit.fill,
    filterQuality: FilterQuality.medium,
  );
}

Future<ui.Image> _decodeRgba(FrameBuffer frame) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(frame.rgba);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: frame.width,
      height: frame.height,
      rowBytes: frame.width * 4,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    codec = await descriptor.instantiateCodec();
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
