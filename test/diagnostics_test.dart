import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'package:windows_doc_capture/src/diagnostics/capture_diagnostics.dart';
import 'controller_test.dart' show FakeSource;
import 'fixtures.dart';
import 'preview_status_test.dart' show analyzeFrame;

const secret = '/private/ID-12345-medical-record.jpg';

class _PrivateSource extends FakeSource {
  @override
  Future<List<CameraDevice>> listDevices() async => [
    const CameraDevice(id: secret, name: secret),
  ];
}

class _DeniedSource extends FakeSource {
  @override
  Future<void> start({
    String? deviceId,
    ResolutionPreset preset = ResolutionPreset.high,
  }) async {
    throw PlatformException(
      code: 'camera_access_denied',
      message: secret,
      details: secret,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DebugPrintCallback previous;
  late List<String> output;
  setUp(() {
    previous = debugPrint;
    output = [];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) output.add(message);
    };
  });
  tearDown(() {
    debugPrint = previous;
  });
  List<Map<String, dynamic>> records() => output.map((l) {
    expect(l, startsWith('[windows_doc_capture] '));
    return jsonDecode(l.substring('[windows_doc_capture] '.length))
        as Map<String, dynamic>;
  }).toList();

  test('debug builds enable production diagnostics by default', () async {
    final source = FakeSource();
    final c = WindowsDocCapture(frameSource: source);
    expect(c.enableDebugLogging, isTrue);
    await c.dispose();
    await source.stream.close();
  });
  test('logging disabled leaves the camera flow silent', () async {
    final source = FakeSource();
    final c = WindowsDocCapture.testing(
      frameSource: source,
      enableDebugLogging: false,
    );
    await c.start();
    source.latest = fixture();
    await c.captureNow();
    await c.dispose();
    await source.stream.close();
    expect(output, isEmpty);
  });
  test(
    'session, quality and capture logs are copyable JSON without identifiers or image data',
    () async {
      final source = _PrivateSource();
      final c = WindowsDocCapture.testing(
        frameSource: source,
        enableDebugLogging: true,
      );
      final errors = c.errors.listen((_) {});
      await c.listDevices();
      await c.start(
        deviceId: secret,
        saveDirectory: null,
        enableAutoCapture: false,
        onDocumentStateChanged: (state) {
          if (state == DocumentPreviewState.clear) throw StateError(secret);
        },
      );
      await analyzeFrame(c, source, fixture());
      source.latest = fixture();
      expect(await c.captureNow(), isNotNull);
      await c.dispose();
      await errors.cancel();
      await source.stream.close();
      final logs = records();
      final events = logs.map((r) => r['event']);
      expect(
        events,
        containsAllInOrder([
          'enumeration_start',
          'enumeration_complete',
          'start',
          'started',
          'capture_start',
          'snapshot',
          'capture_complete',
          'dispose',
          'stopped',
          'disposed',
        ]),
      );
      expect(
        logs.singleWhere(
          (r) => r['event'] == 'start',
        )['specificDeviceRequested'],
        isTrue,
      );
      expect(
        logs.singleWhere((r) => r['event'] == 'capture_complete')['outcome'],
        'success',
      );
      expect(
        logs
            .where((r) => r['event'] == 'error')
            .any((r) => r['stage'] == 'preview_callback'),
        isTrue,
      );
      expect(output.join(), isNot(contains(secret)));
      expect(output.join(), isNot(contains('rgba')));
      expect(logs.map((r) => r['id']).toSet(), hasLength(1));
      expect(
        logs.every(
          (r) => r['v'] == 1 && r['time'] is String && r['uptimeMs'] is int,
        ),
        isTrue,
      );
    },
  );
  test(
    'start errors preserve safe platform codes and redact native details',
    () async {
      final source = _DeniedSource();
      final c = WindowsDocCapture.testing(
        frameSource: source,
        enableDebugLogging: true,
      );
      await expectLater(c.start(), throwsA(isA<PlatformException>()));
      await c.dispose();
      await source.stream.close();
      final error = records().singleWhere((r) => r['event'] == 'error');
      expect(error['stage'], 'start');
      expect(error['platformCode'], 'camera_access_denied');
      expect(output.join(), isNot(contains(secret)));
    },
  );
  test(
    'filesystem diagnostics retain OS code without paths or exception messages',
    () {
      final d = CaptureDiagnostics(enabled: true);
      d.error(
        'capture',
        const FileSystemException(secret, secret, OSError(secret, 13)),
      );
      final log = records().single;
      expect(log['osCode'], 13);
      expect(log['type'], 'FileSystemException');
      expect(output.join(), isNot(contains(secret)));
    },
  );
  test('worker errors retain only package locations from their remote stack', () {
    final d = CaptureDiagnostics(enabled: true);
    d.error(
      'capture',
      RemoteError(
        secret,
        '#0 function (package:windows_doc_capture/src/capture/crop_pipeline.dart:42:3)\n#1 $secret',
      ),
    );
    final log = records().single;
    expect(log['frames'], [
      'package:windows_doc_capture/src/capture/crop_pipeline.dart:42:3',
    ]);
    expect(output.join(), isNot(contains(secret)));
  });
  test(
    'rapid quality transitions are coalesced and terminal states still print',
    () {
      final d = CaptureDiagnostics(enabled: true);
      var previous = DocumentPreviewStatus(
        state: DocumentPreviewState.processing,
      );
      for (var i = 0; i < 100; i++) {
        final next = DocumentPreviewStatus(
          state: i.isEven
              ? DocumentPreviewState.clear
              : DocumentPreviewState.blurry,
        );
        d.state(previous, next);
        previous = next;
      }
      d.state(
        previous,
        DocumentPreviewStatus(state: DocumentPreviewState.idle),
      );
      final logs = records();
      expect(logs.length, lessThan(10));
      expect(logs.last['state'], 'idle');
      expect(logs.last['coalesced'], greaterThan(0));
    },
  );
  test('a failing debugPrint cannot interrupt capture or teardown', () async {
    debugPrint = (String? message, {int? wrapWidth}) =>
        throw StateError('sink failed');
    final source = FakeSource();
    final c = WindowsDocCapture.testing(
      frameSource: source,
      enableDebugLogging: true,
    );
    await c.start();
    source.latest = fixture();
    expect(await c.captureNow(), isNotNull);
    await c.dispose();
    expect(source.running, isFalse);
    await source.stream.close();
  });
  test('health heartbeat reports metrics and stops after dispose', () async {
    final source = FakeSource();
    final c = WindowsDocCapture.testing(
      frameSource: source,
      enableDebugLogging: true,
    );
    await c.start(enableAutoCapture: false);
    await analyzeFrame(c, source, fixture());
    await Future<void>.delayed(const Duration(milliseconds: 5100));
    final health = records().firstWhere((r) => r['event'] == 'health');
    expect(health['reports'], greaterThan(0));
    expect(health['rssMiB'], greaterThan(0));
    expect(health['meanAnalysisMs'], isNotNull);
    await c.dispose();
    final count = output.length;
    await Future<void>.delayed(const Duration(milliseconds: 5100));
    expect(output.length, count);
    await source.stream.close();
  });
}
