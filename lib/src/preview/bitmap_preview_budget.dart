/// Small, clock-driven governor; O(1) state and no timers or frame history.
/// Costs expire so an old slow frame cannot hold reduced quality indefinitely.
class BitmapPreviewBudget {
  int level = 0;
  Duration _evaluatedAt = Duration.zero;
  Duration? _healthySince;
  final _sampling = _Cost(), _decode = _Cost(), _ui = _Cost();

  void observe(
    Duration now, {
    Duration? sampling,
    Duration? decode,
    Duration? ui,
  }) {
    if (sampling != null) _sampling.add(now, sampling);
    if (decode != null) _decode.add(now, decode);
    if (ui != null) _ui.add(now, ui);
    if (now - _evaluatedAt < const Duration(seconds: 1)) return;
    _evaluatedAt = now;
    final sample = _sampling.at(now),
        decoded = _decode.at(now),
        frame = _ui.at(now);
    if (sample >= 8000 || decoded >= 24000 || frame >= 22000) {
      if (level < 2) level++;
      _healthySince = null;
    } else if (sample < 4000 && decoded < 12000 && frame < 14000) {
      _healthySince ??= now;
      if (level > 0 && now - _healthySince! >= const Duration(seconds: 10)) {
        level--;
        _healthySince = now;
      }
    } else {
      _healthySince = null;
    }
  }
}

class _Cost {
  double value = 0;
  Duration? last;
  void add(Duration now, Duration cost) {
    value = last == null || now - last! > const Duration(seconds: 2)
        ? cost.inMicroseconds.toDouble()
        : value * .8 + cost.inMicroseconds * .2;
    last = now;
  }

  double at(Duration now) =>
      last == null || now - last! > const Duration(seconds: 2) ? 0 : value;
}
