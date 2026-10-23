import 'dart:ui';
import '../detection/quality_analyzer.dart';
import '../warnings/preview_warning.dart';

/// Quality/lifecycle of the current preview, independent of auto capture.
/// [clear] means all quality checks pass; it does not guarantee motion stability.
enum DocumentPreviewState {
  idle,
  processing,
  noDocument,
  outOfFrame,
  tooDark,
  tooBright,
  blurry,
  tilted,
  clear,
  capturing,
  cooldown,
  error,
}

/// Immutable UI snapshot. Corners are clockwise TL, TR, BR, BL, normalized to
/// the unmirrored camera frame, not the preview widget or screen dimensions.
class DocumentPreviewStatus {
  DocumentPreviewStatus({
    required this.state,
    List<Offset>? normalizedQuad,
    List<PreviewWarning> warnings = const [],
    this.report,
  }) : normalizedQuad = normalizedQuad == null
           ? null
           : List.unmodifiable(normalizedQuad),
       warnings = List.unmodifiable(warnings) {
    if (normalizedQuad != null &&
        (normalizedQuad.length != 4 ||
            normalizedQuad.any((p) => !p.dx.isFinite || !p.dy.isFinite))) {
      throw ArgumentError('Expected four finite normalized corners');
    }
  }

  factory DocumentPreviewStatus.fromReport(
    QualityReport report, {
    required List<PreviewWarning> warnings,
    DocumentPreviewState? state,
  }) => DocumentPreviewStatus(
    state:
        state ??
        (!report.result.hasDocument || report.result.quad == null
            ? DocumentPreviewState.noDocument
            : stateForWarnings(warnings)),
    normalizedQuad: report.result.hasDocument
        ? report.result.quad
              ?.map(
                (p) => Offset(
                  p.dx / report.frameSize.width,
                  p.dy / report.frameSize.height,
                ),
              )
              .toList()
        : null,
    warnings: warnings,
    report: report,
  );

  final DocumentPreviewState state;
  final List<Offset>? normalizedQuad;
  final List<PreviewWarning> warnings;
  final QualityReport? report;

  bool get isClear =>
      normalizedQuad != null &&
      warnings.isEmpty &&
      (state == DocumentPreviewState.clear ||
          state == DocumentPreviewState.capturing ||
          state == DocumentPreviewState.cooldown);

  /// Multiple problems remain available in [warnings]; this is the primary
  /// state in order of framing, lighting, sharpness, then perspective.
  static DocumentPreviewState stateForWarnings(List<PreviewWarning> warnings) {
    const priority = <WarningType, DocumentPreviewState>{
      WarningType.noDocument: DocumentPreviewState.noDocument,
      WarningType.outOfFrame: DocumentPreviewState.outOfFrame,
      WarningType.tooDark: DocumentPreviewState.tooDark,
      WarningType.tooBright: DocumentPreviewState.tooBright,
      WarningType.blur: DocumentPreviewState.blurry,
      WarningType.tilt: DocumentPreviewState.tilted,
    };
    for (final entry in priority.entries) {
      if (warnings.any((w) => w.type == entry.key)) return entry.value;
    }
    return DocumentPreviewState.clear;
  }
}
