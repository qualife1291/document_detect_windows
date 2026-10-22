import '../detection/detection_result.dart';

enum WarningType { noDocument, outOfFrame, blur, tilt, tooDark, tooBright }

class PreviewWarning {
  const PreviewWarning({
    required this.type,
    required this.message,
    required this.severity,
  });
  final WarningType type;
  final String message;
  final double severity;
}

class QualityThresholds {
  const QualityThresholds({
    this.blurThreshold = 100,
    this.minimumCoverage = .15,
    this.minimumMargin = .02,
    this.maximumTilt = 15,
    this.minimumBrightness = .2,
    this.maximumBrightness = .85,
    this.maximumClipping = .25,
  }) : assert(blurThreshold >= 0),
       assert(minimumCoverage > 0 && minimumCoverage <= 1),
       assert(minimumMargin >= 0 && minimumMargin < .5),
       assert(maximumTilt >= 0),
       assert(minimumBrightness >= 0 && minimumBrightness < maximumBrightness),
       assert(maximumBrightness <= 1),
       assert(maximumClipping >= 0 && maximumClipping <= 1);
  final double blurThreshold, minimumCoverage, minimumMargin, maximumTilt;
  final double minimumBrightness, maximumBrightness, maximumClipping;

  List<PreviewWarning> warningsFor(DetectionResult r) {
    if (!r.hasDocument || r.quad == null) {
      return [
        const PreviewWarning(
          type: WarningType.noDocument,
          message: 'Đưa giấy tờ vào khung',
          severity: 1,
        ),
      ];
    }
    final out = <PreviewWarning>[];
    void add(WarningType type, String text, double severity) => out.add(
      PreviewWarning(
        type: type,
        message: text,
        severity: severity.clamp(0, 1).toDouble(),
      ),
    );
    if (r.edgeMargin < minimumMargin || r.coverageRatio < minimumCoverage) {
      add(
        WarningType.outOfFrame,
        'Đặt trọn giấy tờ vào khung và đưa gần hơn',
        1,
      );
    }
    if (r.blurScore < blurThreshold) {
      add(
        WarningType.blur,
        'Ảnh bị mờ, giữ yên',
        1 - r.blurScore / (blurThreshold == 0 ? 1 : blurThreshold),
      );
    }
    if (r.tiltAngle > maximumTilt) {
      add(WarningType.tilt, 'Giấy tờ bị lệch', r.tiltAngle / 90);
    }
    if (r.brightnessScore < minimumBrightness) {
      add(WarningType.tooDark, 'Quá tối', 1 - r.brightnessScore);
    }
    if (r.brightnessScore > maximumBrightness ||
        r.clippingRatio > maximumClipping) {
      add(
        WarningType.tooBright,
        'Quá sáng',
        r.clippingRatio > maximumClipping ? r.clippingRatio : r.brightnessScore,
      );
    }
    return List.unmodifiable(out);
  }
}
