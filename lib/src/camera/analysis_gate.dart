/// Rate limiting for pull adapters. Reserve at native sampling time, before
/// copying/downsampling; otherwise a 100 ms poll plus copy time becomes 5 FPS.
class AnalysisGate {
  AnalysisGate(this.interval);
  final Duration interval;
  Duration? _last, _requested;

  bool canSubmit(Duration now) =>
      _requested != null || _due(now, Duration.zero);

  bool request(Duration now) {
    // Allow bounded timer jitter, not another whole polling period. Push-only
    // sources retain the strict interval check in canSubmit().
    final slack = Duration(
      microseconds: (interval.inMicroseconds ~/ 10).clamp(0, 5000),
    );
    if (!_due(now, slack)) return false;
    _requested = now;
    return true;
  }

  bool _due(Duration now, Duration slack) =>
      _last == null || now + slack - _last! >= interval;

  void submitted(Duration now) {
    _last = _requested ?? now;
    _requested = null;
  }

  void discardRequest() => _requested = null;
  void reset() {
    _last = null;
    _requested = null;
  }
}
