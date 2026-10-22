import 'dart:async';
import 'dart:isolate';
import '../camera/frame_source.dart';
import 'detection_result.dart';
import 'detector_facade.dart';

class QualityReport {
  const QualityReport({
    required this.result,
    required this.frameSize,
    required this.capturedAt,
    required this.sequence,
    required this.analysisTime,
  });
  final DetectionResult result;
  final ({int width, int height}) frameSize;
  final DateTime capturedAt;
  final int sequence;
  final Duration analysisTime;
}

/// One active frame + one pending latest frame. The native preview is independent.
class DocumentQualityAnalyzer {
  DocumentQualityAnalyzer({this.maxWidth = 640}) {
    if (maxWidth < 32 || maxWidth > 1920) {
      throw ArgumentError.value(maxWidth, 'maxWidth');
    }
  }
  final int maxWidth;
  final _reports = StreamController<QualityReport>.broadcast();
  Stream<QualityReport> get reports => _reports.stream;
  final _ready = Completer<SendPort>();
  ReceivePort? _receive;
  Isolate? _isolate;
  Future<void>? _starting;
  bool _busy = false, _closed = false;
  FrameBuffer? _pending;
  int droppedFrames = 0;
  int get pendingFrames => _pending == null ? 0 : 1;

  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    if (_closed) throw StateError('Analyzer closed');
    _receive = ReceivePort();
    _receive!.listen((dynamic message) {
      if (message is SendPort) {
        _ready.complete(message);
        return;
      }
      if (_closed) return;
      _busy = false;
      if (message is QualityReport) {
        _reports.add(message);
      } else {
        _reports.addError(StateError('Document analysis failed'));
      }
      final next = _pending;
      _pending = null;
      if (next != null) _send(next);
    });
    _isolate = await Isolate.spawn(_worker, (_receive!.sendPort, maxWidth));
    await _ready.future.timeout(const Duration(seconds: 10));
  }

  void add(FrameBuffer frame) {
    if (_closed || !_ready.isCompleted) return;
    if (_busy) {
      if (_pending != null) droppedFrames++;
      _pending = frame;
    } else {
      _send(frame);
    }
    assert(pendingFrames <= 1);
  }

  void _send(FrameBuffer f) {
    _busy = true;
    _ready.future.then((port) {
      if (!_closed) {
        port.send((
          f.width,
          f.height,
          TransferableTypedData.fromList([f.rgba]),
          f.capturedAt,
          f.sequence,
        ));
      }
    });
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _pending = null;
    if (_starting != null) {
      try {
        await _starting;
      } catch (_) {
        /* start failure is propagated to caller */
      }
    }
    _isolate?.kill(priority: Isolate.immediate);
    _receive?.close();
    await _reports.close();
  }
}

void _worker((SendPort, int) init) {
  final detector = createDocumentDetector(maxWidth: init.$2);
  final input = ReceivePort();
  init.$1.send(input.sendPort);
  input.listen((dynamic message) async {
    try {
      final m = message as (int, int, TransferableTypedData, DateTime, int);
      final watch = Stopwatch()..start();
      final frame = FrameBuffer(
        width: m.$1,
        height: m.$2,
        rgba: m.$3.materialize().asUint8List(),
        capturedAt: m.$4,
        sequence: m.$5,
      );
      final result = await detector.detect(frame);
      init.$1.send(
        QualityReport(
          result: result,
          frameSize: (width: frame.width, height: frame.height),
          capturedAt: frame.capturedAt,
          sequence: frame.sequence,
          analysisTime: watch.elapsed,
        ),
      );
    } catch (_) {
      init.$1.send('analysisError');
    }
  });
}
