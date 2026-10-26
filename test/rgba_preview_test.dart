import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'fixtures.dart';

Future<ui.Image> image() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const Color(0xff663399), ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(8, 8);
  } finally {
    picture.dispose();
  }
}

void main() {
  testWidgets(
    'new session rejects late decode even when its stream is reused',
    (tester) async {
      final frames = StreamController<FrameBuffer>.broadcast();
      final stream = frames.stream;
      final oldDemand = BitmapPreviewDemand(),
          newDemand = BitmapPreviewDemand();
      final gate = Completer<ui.Image>();
      var calls = 0;
      Widget tree(BitmapPreviewDemand demand) => RgbaCameraPreview.testing(
        frames: stream,
        frameDemand: demand,
        decodeFrame: (_) {
          calls++;
          return gate.future;
        },
      );
      await tester.pumpWidget(tree(oldDemand));
      frames.add(fixture(width: 8, height: 8));
      await tester.pump();
      await tester.pumpWidget(tree(newDemand));
      expect(oldDemand.canAcceptFrame, isFalse);
      expect(newDemand.canAcceptFrame, isFalse);
      frames.add(fixture(width: 8, height: 8));
      await tester.pump();
      expect(calls, 1); // no overlapping native decoder
      final late = (await tester.runAsync(image))!;
      gate.complete(late);
      await tester.pumpAndSettle();
      expect(late.debugDisposed, isTrue);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNull);
      expect(newDemand.canAcceptFrame, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await frames.close();
    },
  );

  testWidgets(
    'hidden and inactive consumers refuse new decode and recover safely',
    (tester) async {
      final frames = StreamController<FrameBuffer>.broadcast();
      final demand = BitmapPreviewDemand();
      var decodes = 0;
      final seed = (await tester.runAsync(image))!;
      final stableStream = frames.stream;
      Widget tree(bool enabled) => TickerMode(
        enabled: enabled,
        child: RgbaCameraPreview.testing(
          frames: stableStream,
          frameDemand: demand,
          decodeFrame: (_) async {
            decodes++;
            return seed.clone();
          },
        ),
      );
      try {
        await tester.pumpWidget(tree(false));
        expect(demand.canAcceptFrame, isFalse);
        frames.add(fixture(width: 8, height: 8));
        await tester.pump();
        expect(decodes, 0);
        await tester.pumpWidget(tree(true));
        expect(demand.canAcceptFrame, isTrue);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        expect(demand.canAcceptFrame, isFalse);
        frames.add(fixture(width: 8, height: 8));
        await tester.pump();
        expect(decodes, 0);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        frames.add(fixture(width: 8, height: 8));
        await tester.pumpAndSettle();
        expect(decodes, 1);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        expect(demand.canAcceptFrame, isFalse);
        seed.dispose();
        await frames.close();
      }
    },
  );

  testWidgets(
    'bitmap preview drops busy frames and disposes replaced/closed images',
    (tester) async {
      final frames = StreamController<FrameBuffer>.broadcast();
      final demand = BitmapPreviewDemand();
      expect(demand.canAcceptFrame, isFalse);
      final gates = <Completer<ui.Image>>[];
      await tester.pumpWidget(
        RgbaCameraPreview.testing(
          frames: frames.stream,
          frameDemand: demand,
          decodeFrame: (_) {
            final gate = Completer<ui.Image>();
            gates.add(gate);
            return gate.future;
          },
        ),
      );
      expect(demand.canAcceptFrame, isTrue);
      for (var i = 0; i < 40; i++) {
        frames.add(fixture(width: 8, height: 8, sequence: i));
      }
      await tester.pump();
      expect(gates, hasLength(1));
      expect(demand.canAcceptFrame, isFalse);
      final first = (await tester.runAsync(image))!;
      gates[0].complete(first);
      await tester.pumpAndSettle();
      expect(demand.canAcceptFrame, isTrue);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(first));
      frames.add(fixture(width: 8, height: 8));
      await tester.pump();
      expect(gates, hasLength(2));
      final second = (await tester.runAsync(image))!;
      gates[1].complete(second);
      await tester.pumpAndSettle();
      expect(first.debugDisposed, isTrue);
      expect(second.debugDisposed, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(second.debugDisposed, isTrue);
      expect(demand.canAcceptFrame, isFalse);
      expect(frames.hasListener, isFalse);
      await frames.close();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'repeated decode without painting releases every superseded image',
    (tester) async {
      final frames = StreamController<FrameBuffer>.broadcast(sync: true);
      final seed = (await tester.runAsync(image))!;
      final created = <ui.Image>[];
      await tester.pumpWidget(
        RgbaCameraPreview.testing(
          frames: frames.stream,
          decodeFrame: (_) {
            final result = seed.clone();
            created.add(result);
            return Future.value(result);
          },
        ),
      );
      for (var i = 0; i < 30; i++) {
        frames.add(fixture(width: 8, height: 8, sequence: i));
        await tester
            .idle(); // Flush decode completion without presenting a frame.
      }
      expect(created, hasLength(30));
      expect(created.take(29).every((value) => value.debugDisposed), isTrue);
      expect(created.last.debugDisposed, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(created.every((value) => value.debugDisposed), isTrue);
      seed.dispose();
      await frames.close();
    },
  );
  testWidgets(
    'unmount during decode disposes the late result without setState',
    (tester) async {
      final frames = StreamController<FrameBuffer>.broadcast();
      final gate = Completer<ui.Image>();
      await tester.pumpWidget(
        RgbaCameraPreview.testing(
          frames: frames.stream,
          decodeFrame: (_) => gate.future,
        ),
      );
      frames.add(fixture(width: 8, height: 8));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      final late = (await tester.runAsync(image))!;
      gate.complete(late);
      await tester.pump();
      expect(late.debugDisposed, isTrue);
      expect(tester.takeException(), isNull);
      await frames.close();
    },
  );
  testWidgets(
    'stream change discards old decode and releases old subscription',
    (tester) async {
      final a = StreamController<FrameBuffer>.broadcast(),
          b = StreamController<FrameBuffer>.broadcast();
      final oldDemand = BitmapPreviewDemand(),
          newDemand = BitmapPreviewDemand();
      final gate = Completer<ui.Image>();
      await tester.pumpWidget(
        RgbaCameraPreview.testing(
          frames: a.stream,
          frameDemand: oldDemand,
          decodeFrame: (_) => gate.future,
        ),
      );
      a.add(fixture(width: 8, height: 8));
      await tester.pump();
      await tester.pumpWidget(
        RgbaCameraPreview.testing(
          frames: b.stream,
          frameDemand: newDemand,
          decodeFrame: (_) => gate.future,
        ),
      );
      expect(oldDemand.canAcceptFrame, isFalse);
      expect(newDemand.canAcceptFrame, isFalse);
      expect(a.hasListener, isFalse);
      expect(b.hasListener, isTrue);
      final late = (await tester.runAsync(image))!;
      gate.complete(late);
      await tester.pump();
      expect(late.debugDisposed, isTrue);
      expect(oldDemand.canAcceptFrame, isFalse);
      expect(newDemand.canAcceptFrame, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await a.close();
      await b.close();
    },
  );
  testWidgets(
    'decode errors recover, source errors are not fed back into source',
    (tester) async {
      final frames = StreamController<FrameBuffer>.broadcast();
      var failures = 0, calls = 0;
      await tester.pumpWidget(
        RgbaCameraPreview.testing(
          frames: frames.stream,
          decodeFrame: (_) {
            calls++;
            return Future.error(StateError('decode'));
          },
          onDecodeError: (_, __) {
            failures++;
          },
        ),
      );
      frames.addError(StateError('source'));
      await tester.pump();
      expect(failures, 0);
      for (var i = 0; i < 2; i++) {
        frames.add(fixture(width: 8, height: 8));
        await tester.pump();
      }
      expect(failures, 2);
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await frames.close();
    },
  );
  testWidgets('real RGBA decode is bounded and does not use the image cache', (
    tester,
  ) async {
    final frames = StreamController<FrameBuffer>.broadcast();
    final cache = PaintingBinding.instance.imageCache;
    final entries = cache.currentSize;
    await tester.pumpWidget(
      RgbaCameraPreview(frames: frames.stream, maxDimension: 16),
    );
    await tester.runAsync(() async {
      frames.add(fixture(width: 18, height: 8));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNull);
    await tester.runAsync(() async {
      frames.add(fixture(width: 16, height: 8));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pump();
    for (
      var i = 0;
      i < 40 && tester.widget<RawImage>(find.byType(RawImage)).image == null;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    final decoded = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(decoded.width, 16);
    expect(decoded.height, 8);
    expect(cache.currentSize, entries);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(decoded.debugDisposed, isTrue);
    await frames.close();
  });
}
