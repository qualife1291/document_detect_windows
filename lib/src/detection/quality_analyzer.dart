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
  Future<void>? _starting, _disposing;
  SendPort? _port;
  Timer? _watchdog;
  bool _busy = false, _closed = false, _failed = false;
  FrameBuffer? _pending;
  int droppedFrames = 0;
  bool get canAcceptFrame => !_closed && !_failed && _port != null && !_busy;
  int get pendingFrames => _pending == null ? 0 : 1;

  Future<void> start() {
    if (_closed || _failed) {
      return Future.error(StateError('Analyzer closed or failed'));
    }
    return _starting ??= _start();
  }

  Future<void> _start() async {
    if (_closed) throw StateError('Analyzer closed');
    _receive = ReceivePort();
    _receive!.listen((dynamic message) {
      if (message is SendPort) {
        _port = message;
        if (!_ready.isCompleted) _ready.complete(message);
        return;
      }
      if (_closed) return;
      _watchdog?.cancel();
      if (message is! QualityReport && message != 'analysisError') {
        _fail(StateError('Document analysis worker exited'));
        return;
      }
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
    final ready = _ready.future;
    unawaited(ready.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    try {
      _isolate = await Isolate.spawn(
        _worker,
        (_receive!.sendPort, maxWidth),
        onError: _receive!.sendPort,
        onExit: _receive!.sendPort,
        errorsAreFatal: true,
      );
      await ready.timeout(const Duration(seconds: 10));
    } catch (_) {
      _failed = true;
      _port = null;
      _isolate?.kill(priority: Isolate.immediate);
      _receive?.close();
      rethrow;
    }
  }

  void add(FrameBuffer frame) {
    if (_closed || _failed || _port == null) return;
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
    _port!.send((
      f.width,
      f.height,
      TransferableTypedData.fromList([f.rgba]),
      f.capturedAt,
      f.sequence,
    ));
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 5), () {
      if (!_closed) {
        _fail(TimeoutException('Document analysis stalled'));
      }
    });
  }

  void _fail(Object error) {
    if (_closed || _failed) return;
    _failed = true;
    _busy = false;
    _pending = null;
    _port = null;
    _watchdog?.cancel();
    _isolate?.kill(priority: Isolate.immediate);
    if (!_ready.isCompleted) {
      _ready.completeError(error);
    } else {
      _reports.addError(error);
    }
  }

  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    if (_closed) return;
    _closed = true;
    _pending = null;
    _watchdog?.cancel();
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
