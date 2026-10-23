import 'dart:math' as math;
import 'dart:ui';
import '../detection/detection_result.dart';
import '../warnings/preview_warning.dart';

enum AutoCaptureState { idle, detecting, stable, capturing, cooldown }

class AutoCaptureController {
  AutoCaptureController({
    this.thresholds = const QualityThresholds(),
    this.stableFrameCount = 8,
    this.feedbackDuration = const Duration(milliseconds: 500),
    this.cooldown = const Duration(seconds: 2),
    this.maxFrameGap = const Duration(milliseconds: 400),
    this.maximumMotion = .015,
  }) {
    if (stableFrameCount < 1 ||
        feedbackDuration < const Duration(milliseconds: 500) ||
        cooldown < Duration.zero ||
        maxFrameGap <= Duration.zero ||
        maximumMotion <= 0) {
      throw ArgumentError('Invalid auto-capture configuration');
    }
  }
  final QualityThresholds thresholds;
  final int stableFrameCount;
  final Duration feedbackDuration, cooldown, maxFrameGap;
  final double maximumMotion;
  AutoCaptureState state = AutoCaptureState.idle;
  int stableFrames = 0;
  Duration? _stableSince, _lastFrame, _cooldownUntil;
  List<Offset>? _anchor;
  bool _needsRemoval = false;
  double feedbackProgress = 0;

  /// [now] comes from a monotonic stopwatch; quad is normalized to [0,1].
  bool update(
    DetectionResult result,
    List<Offset>? normalizedQuad,
    Duration now,
  ) {
    if (state == AutoCaptureState.capturing) return false;
    if (_needsRemoval) {
      if (!result.hasDocument) _needsRemoval = false;
      if (_needsRemoval || (_cooldownUntil != null && now < _cooldownUntil!)) {
        state = AutoCaptureState.cooldown;
        return false;
      }
    }
    if (_cooldownUntil != null && now < _cooldownUntil!) {
      state = AutoCaptureState.cooldown;
      return false;
    }
    final continuous =
        _lastFrame == null ||
        (now > _lastFrame! && now - _lastFrame! <= maxFrameGap);
    _lastFrame = now;
    if (thresholds.warningsFor(result).isNotEmpty ||
        normalizedQuad == null ||
        normalizedQuad.length != 4) {
      _reset();
      return false;
    }
    var motion = 0.0;
    if (_anchor != null) {
      for (var i = 0; i < 4; i++) {
        motion = math.max(motion, (normalizedQuad[i] - _anchor![i]).distance);
      }
    }
    if (!continuous || motion > maximumMotion) {
      _reset();
    }
    _anchor ??= List.of(normalizedQuad);
    stableFrames++;
    _stableSince ??= now;
    state = AutoCaptureState.stable;
    feedbackProgress =
        ((now - _stableSince!).inMicroseconds / feedbackDuration.inMicroseconds)
            .clamp(0, 1)
            .toDouble();
    if (stableFrames >= stableFrameCount &&
        now - _stableSince! >= feedbackDuration) {
      state = AutoCaptureState.capturing;
      return true;
    }
    return false;
  }

  void captureCompleted(Duration now) {
    _reset();
    _cooldownUntil = now + cooldown;
    _needsRemoval = true;
    state = AutoCaptureState.cooldown;
  }

  /// Missing/stale analysis must not rearm a captured document still in view.
  void invalidateFrames() {
    _lastFrame = null;
    stableFrames = 0;
    _stableSince = null;
    _anchor = null;
    feedbackProgress = 0;
    if (state != AutoCaptureState.capturing &&
        state != AutoCaptureState.cooldown) {
      state = AutoCaptureState.detecting;
    }
  }

  void reset() {
    _cooldownUntil = null;
    _needsRemoval = false;
    _lastFrame = null;
    _reset();
    state = AutoCaptureState.idle;
  }

  void _reset() {
    stableFrames = 0;
    _stableSince = null;
    _anchor = null;
    feedbackProgress = 0;
    state = AutoCaptureState.detecting;
  }
}
