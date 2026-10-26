import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import '../camera/frame_source.dart';

/// One bitmap consumer's readiness. Create a new handle for each camera session.
/// Sources read this before costly native readback; only the widget mutates it.
class BitmapPreviewDemand {
  bool _ready = false;
  bool get canAcceptFrame => _ready;
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

class _RgbaCameraPreviewState extends State<RgbaCameraPreview> {
  StreamSubscription<FrameBuffer>? _subscription;
  ui.Image? _image;
  bool _decoding = false;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    _listen();
    _updateDemand();
  }

  void _updateDemand() {
    widget.frameDemand?._ready = mounted && !_decoding;
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
    if (!identical(oldWidget.frames, widget.frames)) {
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
        !mounted ||
        frame.width > widget.maxDimension ||
        frame.height > widget.maxDimension) {
      return;
    }
    _decoding = true;
    _updateDemand();
    final epoch = _epoch;
    unawaited(_decode(frame, epoch));
  }

  Future<void> _decode(FrameBuffer frame, int epoch) async {
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
      _decoding = false;
      if (mounted) _updateDemand();
    }
  }

  @override
  void dispose() {
    ++_epoch;
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
    filterQuality: FilterQuality.low,
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
