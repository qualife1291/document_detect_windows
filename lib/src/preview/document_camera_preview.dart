import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../camera/frame_source.dart';
import 'document_preview_status.dart';

/// Maps camera-normalized corners through the same BoxFit and alignment used
/// by the native preview. Includes letterboxing, cropping and nonuniform fill.
List<Offset> projectDocumentQuad({
  required List<Offset> normalizedQuad,
  required Size imageSize,
  required Size viewportSize,
  BoxFit fit = BoxFit.contain,
  Alignment alignment = Alignment.center,
}) {
  if (imageSize.isEmpty ||
      viewportSize.isEmpty ||
      !imageSize.width.isFinite ||
      !imageSize.height.isFinite ||
      !viewportSize.width.isFinite ||
      !viewportSize.height.isFinite) {
    return const [];
  }
  final fitted = applyBoxFit(fit, imageSize, viewportSize);
  final source = alignment.inscribe(fitted.source, Offset.zero & imageSize);
  final destination = alignment.inscribe(
    fitted.destination,
    Offset.zero & viewportSize,
  );
  return normalizedQuad
      .map(
        (p) => Offset(
          destination.left +
              (p.dx * imageSize.width - source.left) *
                  destination.width /
                  source.width,
          destination.top +
              (p.dy * imageSize.height - source.top) *
                  destination.height /
                  source.height,
        ),
      )
      .toList(growable: false);
}

/// Native camera texture and four document corner markers in one coordinate
/// space. This widget never reads or renders analysis-frame pixel bytes.
class DocumentCameraPreview extends StatelessWidget {
  const DocumentCameraPreview({
    super.key,
    required this.frameSource,
    required this.status,
    this.showDocumentCorners = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.validColor = const Color(0xff69f0ae),
    this.warningColor = const Color(0xffffcc80),
    this.strokeWidth = 3,
    this.cornerLength = 24,
  }) : assert(strokeWidth > 0),
       assert(cornerLength > 0);

  final FrameSource frameSource;
  final ValueListenable<DocumentPreviewStatus> status;
  final bool showDocumentCorners;
  final BoxFit fit;
  final Alignment alignment;
  final Color validColor, warningColor;
  final double strokeWidth, cornerLength;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<DocumentPreviewStatus>(
        valueListenable: status,
        builder: (context, value, _) => LayoutBuilder(
          builder: (context, constraints) {
            final cameraSize = frameSource.previewSize;
            final ready =
                value.state != DocumentPreviewState.idle &&
                value.state != DocumentPreviewState.error &&
                !cameraSize.isEmpty &&
                cameraSize.width.isFinite &&
                cameraSize.height.isFinite;
            final natural = ready ? cameraSize : const Size(640, 360);
            final preferred =
                constraints.hasBoundedWidth && constraints.hasBoundedHeight
                ? constraints.biggest
                : constraints.hasBoundedWidth
                ? Size(
                    constraints.maxWidth,
                    constraints.maxWidth / natural.aspectRatio,
                  )
                : constraints.hasBoundedHeight
                ? Size(
                    constraints.maxHeight * natural.aspectRatio,
                    constraints.maxHeight,
                  )
                : natural;
            final viewport = constraints.constrain(preferred);
            return SizedBox(
              width: viewport.width,
              height: viewport.height,
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0xff000000)),
                    if (ready)
                      FittedBox(
                        fit: fit,
                        alignment: alignment,
                        child: SizedBox(
                          width: cameraSize.width,
                          height: cameraSize.height,
                          child: frameSource.buildPreview(),
                        ),
                      ),
                    if (ready && showDocumentCorners)
                      IgnorePointer(
                        child: CustomPaint(
                          painter: DocumentCornersPainter(
                            normalizedQuad: value.normalizedQuad,
                            imageSize: cameraSize,
                            fit: fit,
                            alignment: alignment,
                            color: value.isClear ? validColor : warningColor,
                            strokeWidth: strokeWidth,
                            cornerLength: cornerLength,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

/// Draws L-shaped markers along adjacent document edges, including perspective.
class DocumentCornersPainter extends CustomPainter {
  DocumentCornersPainter({
    required List<Offset>? normalizedQuad,
    required this.imageSize,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.color = const Color(0xff69f0ae),
    this.strokeWidth = 3,
    this.cornerLength = 24,
  }) : normalizedQuad = normalizedQuad == null
           ? null
           : List.unmodifiable(normalizedQuad),
       assert(strokeWidth > 0),
       assert(cornerLength > 0);

  final List<Offset>? normalizedQuad;
  final Size imageSize;
  final BoxFit fit;
  final Alignment alignment;
  final Color color;
  final double strokeWidth, cornerLength;

  @override
  void paint(Canvas canvas, Size size) {
    final quad = normalizedQuad;
    if (quad == null || quad.length != 4) return;
    final points = projectDocumentQuad(
      normalizedQuad: quad,
      imageSize: imageSize,
      viewportSize: size,
      fit: fit,
      alignment: alignment,
    );
    if (points.length != 4 ||
        points.any((p) => !p.dx.isFinite || !p.dy.isFinite)) {
      return;
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < 4; i++) {
      final corner = points[i];
      final previous = points[(i + 3) % 4] - corner;
      final next = points[(i + 1) % 4] - corner;
      if (previous.distance == 0 || next.distance == 0) continue;
      final a =
          corner +
          previous /
              previous.distance *
              math.min(cornerLength, previous.distance / 3);
      final b =
          corner +
          next / next.distance * math.min(cornerLength, next.distance / 3);
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(b.dx, b.dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(DocumentCornersPainter oldDelegate) =>
      !listEquals(normalizedQuad, oldDelegate.normalizedQuad) ||
      imageSize != oldDelegate.imageSize ||
      fit != oldDelegate.fit ||
      alignment != oldDelegate.alignment ||
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      cornerLength != oldDelegate.cornerLength;
}
