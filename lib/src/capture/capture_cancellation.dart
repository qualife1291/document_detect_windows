import 'dart:async';
import 'dart:isolate';

/// Cancels snapshot waiting and CPU work when a camera session ends. Cancellation
/// is cooperative for native camera requests; a late native result is discarded.
class CaptureCancellation {
  bool _cancelled = false;
  final _listeners = <void Function()>[];
  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void Function() _listen(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  Future<T?> wait<T>(Future<T> future) async {
    final done = Completer<T?>();
    final remove = _listen(() {
      if (!done.isCompleted) done.complete(null);
    });
    // Keep handling the native future after cancellation, including errors.
    unawaited(
      future.then(
        (value) {
          if (!done.isCompleted) done.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (!done.isCompleted) done.completeError(error, stack);
        },
      ),
    );
    try {
      return await done.future;
    } finally {
      remove();
    }
  }
}

/// A bounded worker whose large result exits the isolate without a second copy.
/// Killing it is safe: computation must not perform file/native camera writes.
Future<T?> runCaptureWorker<T>(
  FutureOr<T> Function() computation, {
  CaptureCancellation? cancellation,
  Duration timeout = const Duration(seconds: 60),
}) async {
  if (cancellation?.isCancelled ?? false) return null;
  final receive = ReceivePort();
  final result = Completer<T?>();
  Isolate? worker;
  final subscription = receive.listen((dynamic message) {
    if (result.isCompleted) return;
    if (message is (String, Object?)) {
      result.complete(message.$2 as T);
    } else if (message is List && message.length == 2) {
      result.completeError(RemoteError('${message[0]}', '${message[1]}'));
    } else {
      result.completeError(StateError('Capture worker exited unexpectedly'));
    }
  });
  final remove = cancellation?._listen(() {
    if (!result.isCompleted) result.complete(null);
    worker?.kill(priority: Isolate.immediate);
  });
  final timer = Timer(timeout, () {
    if (!result.isCompleted) {
      result.completeError(
        TimeoutException('Capture processing timed out', timeout),
      );
    }
    worker?.kill(priority: Isolate.immediate);
  });
  try {
    // Attach the consumer before spawn can deliver errors/cancellation.
    final outcome = result.future;
    unawaited(
      outcome.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    worker = await Isolate.spawn(
      _captureEntry<T>,
      (receive.sendPort, computation),
      onError: receive.sendPort,
      onExit: receive.sendPort,
      errorsAreFatal: true,
    );
    if (result.isCompleted) worker.kill(priority: Isolate.immediate);
    return await outcome;
  } finally {
    timer.cancel();
    remove?.call();
    worker?.kill(priority: Isolate.immediate);
    await subscription.cancel();
    receive.close();
  }
}

void _captureEntry<T>((SendPort, FutureOr<T> Function()) message) async {
  final value = await message.$2();
  Isolate.exit(message.$1, ('ok', value));
}
