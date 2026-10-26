import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';

/// Bounded display decode; output JPEG bytes retain their original resolution.
/// Evict only this result's provider when replacing/closing it.
class CaptureResultImage extends StatefulWidget {
  const CaptureResultImage({
    super.key,
    required this.bytes,
    this.maxDimension = 1280,
  });
  final Uint8List bytes;
  final int maxDimension;
  @override
  State<CaptureResultImage> createState() => _CaptureResultImageState();
}

class _CaptureResultImageState extends State<CaptureResultImage> {
  late ImageProvider _provider;
  double? _displayScale;
  ImageProvider _create() => ResizeImage(
    MemoryImage(widget.bytes, scale: _displayScale!),
    width: widget.maxDimension,
    height: widget.maxDimension,
    policy: ResizeImagePolicy.fit,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scale =
        MediaQuery.maybeDevicePixelRatioOf(context) ??
        View.of(context).devicePixelRatio;
    if (_displayScale != scale) {
      if (_displayScale != null) unawaited(_provider.evict());
      _displayScale = scale;
      _provider = _create();
    }
  }

  @override
  void didUpdateWidget(CaptureResultImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.maxDimension != widget.maxDimension) {
      unawaited(_provider.evict());
      _provider = _create();
    }
  }

  @override
  void dispose() {
    unawaited(_provider.evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Image(
    image: _provider,
    // One decoded pixel occupies at most one physical screen pixel. Avoid
    // stretching a small crop across the whole result area, especially at DPI.
    fit: BoxFit.scaleDown,
    filterQuality: FilterQuality.medium,
    semanticLabel: 'Ảnh giấy tờ đã cắt và chỉnh phối cảnh',
  );
}
