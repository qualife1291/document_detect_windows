import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/src/camera/analysis_gate.dart';

Duration ms(int value) => Duration(milliseconds: value);
void main() {
  test('copy time does not halve the cadence of a 100ms pull adapter', () {
    final gate = AnalysisGate(ms(100));
    for (var tick = 0; tick < 20; tick++) {
      expect(gate.request(ms(tick * 100)), isTrue);
      expect(gate.canSubmit(ms(tick * 100 + 25)), isTrue);
      gate.submitted(ms(tick * 100 + 25));
    }
  });
  test(
    'pull jitter allowance is bounded and push-only sources stay strict',
    () {
      final gate = AnalysisGate(ms(100));
      gate.submitted(ms(0));
      expect(gate.request(ms(94)), isFalse);
      expect(gate.canSubmit(ms(99)), isFalse);
      expect(gate.request(ms(96)), isTrue);
      gate.submitted(ms(110));
      expect(gate.canSubmit(ms(195)), isFalse);
      expect(gate.canSubmit(ms(196)), isTrue);
    },
  );
  test('discarded demand and new sessions cannot reuse a reservation', () {
    final gate = AnalysisGate(ms(100));
    gate.submitted(ms(0));
    expect(gate.request(ms(96)), isTrue);
    gate.discardRequest();
    expect(gate.canSubmit(ms(96)), isFalse);
    gate.reset();
    expect(gate.canSubmit(ms(0)), isTrue);
  });
}
