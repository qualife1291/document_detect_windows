import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/src/preview/bitmap_preview_budget.dart';

void main() {
  test(
    'host UI pressure reduces load even when sampling and decode are cheap',
    () {
      final budget = BitmapPreviewBudget();
      for (var s = 0; s <= 3; s++) {
        budget.observe(
          Duration(seconds: s),
          sampling: const Duration(milliseconds: 1),
          decode: const Duration(milliseconds: 2),
          ui: const Duration(milliseconds: 35),
        );
      }
      expect(budget.level, 2);
      // No sudden rebound on a single cheap frame.
      for (var s = 4; s <= 9; s++) {
        budget.observe(
          Duration(seconds: s),
          sampling: const Duration(milliseconds: 1),
          decode: const Duration(milliseconds: 2),
          ui: const Duration(milliseconds: 4),
        );
      }
      expect(budget.level, 2);
      // Old UI cost expires, then each recovery step needs 10 healthy seconds.
      for (var s = 10; s <= 20; s++) {
        budget.observe(
          Duration(seconds: s),
          sampling: const Duration(milliseconds: 1),
        );
      }
      expect(budget.level, 1);
      for (var s = 21; s <= 30; s++) {
        budget.observe(
          Duration(seconds: s),
          sampling: const Duration(milliseconds: 1),
        );
      }
      expect(budget.level, 0);
    },
  );
  test(
    'sampling and slow decoders independently trigger bounded reductions',
    () {
      for (final decode in [true, false]) {
        final budget = BitmapPreviewBudget();
        for (var s = 0; s < 100; s++) {
          budget.observe(
            Duration(seconds: s),
            sampling: decode ? Duration.zero : const Duration(milliseconds: 20),
            decode: decode ? const Duration(milliseconds: 40) : Duration.zero,
          );
        }
        expect(budget.level, 2);
      }
    },
  );
}
