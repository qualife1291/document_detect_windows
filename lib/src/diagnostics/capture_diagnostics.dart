import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../detection/quality_analyzer.dart';
import '../preview/document_preview_status.dart';

/// Local, bounded diagnostic output. Never pass exception messages, paths,
/// camera identifiers, image bytes or document text to the logger.
class CaptureDiagnostics {
  CaptureDiagnostics({required this.enabled});
  final bool enabled;
  static int _nextId = 0;
  late final String _id =
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${++_nextId}';
  final _clock = Stopwatch()..start();
  Duration? _lastState;
  int _suppressed = 0, _session = 0;
  int received = 0, accepted = 0, reports = 0, stale = 0, expired = 0;
  double _analysisMs = 0, _maxAnalysisMs = 0;
  DateTime? _lastFrame;
  Duration _lastHealth = Duration.zero;
  int _lastHealthReports = 0;

  void event(String name, [Map<String, Object?> fields = const {}]) {
    if (!enabled) return;
    try {
      debugPrint(
        '[windows_doc_capture] ${jsonEncode({'v': 1, 'time': DateTime.now().toUtc().toIso8601String(), 'id': _id, 'session': _session, 'uptimeMs': _clock.elapsedMilliseconds, 'event': name, ...fields})}',
        wrapWidth: 4096,
      );
    } catch (_) {
      // Diagnostics (including an app-replaced debugPrint) must never break IO.
    }
  }

  void error(String stage, Object error, [StackTrace? stack]) {
    if (!enabled) return;
    final trace = (error is RemoteError ? error.stackTrace : stack)?.toString();
    event('error', {
      'stage': stage,
      'type': error.runtimeType.toString(),
      if (error is TimeoutException)
        'timeoutMs': error.duration?.inMilliseconds,
      if (error is FileSystemException) 'osCode': error.osError?.errorCode,
      if (error is PlatformException &&
          RegExp(r'^[a-zA-Z0-9_.-]{1,64}$').hasMatch(error.code))
        'platformCode': error.code,
      if (trace != null)
        'frames': RegExp(
          r'package:windows_doc_capture[^\s)]*',
        ).allMatches(trace).take(6).map((m) => m.group(0)).toList(),
    });
  }

  void resetSession() {
    if (!enabled) return;
    _session++;
    received = accepted = reports = stale = expired = 0;
    _analysisMs = _maxAnalysisMs = 0;
    _lastFrame = null;
    _lastHealth = _clock.elapsed;
    _lastHealthReports = 0;
    _lastState = null;
    _suppressed = 0;
  }

  void frame({required bool submitted}) {
    if (!enabled) return;
    received++;
    if (submitted) accepted++;
  }

  void report(QualityReport report) {
    if (!enabled) return;
    reports++;
    final ms = report.analysisTime.inMicroseconds / 1000;
    _analysisMs += ms;
    if (ms > _maxAnalysisMs) _maxAnalysisMs = ms;
    _lastFrame = report.capturedAt;
  }

  Map<String, Object?> snapshot(DocumentPreviewStatus status) {
    final result = status.report?.result;
    return {
      'state': status.state.name,
      'warnings': status.warnings.map((w) => w.type.name).toList(),
      'quad': status.normalizedQuad
          ?.map(
            (p) => [
              double.parse(p.dx.toStringAsFixed(3)),
              double.parse(p.dy.toStringAsFixed(3)),
            ],
          )
          .toList(),
      if (result != null) ...{
        'blur': result.blurScore.round(),
        'brightness': double.parse(result.brightnessScore.toStringAsFixed(3)),
        'clipping': double.parse(result.clippingRatio.toStringAsFixed(3)),
        'coverage': double.parse(result.coverageRatio.toStringAsFixed(3)),
        'margin': double.parse(result.edgeMargin.toStringAsFixed(3)),
        'tiltDeg': double.parse(result.tiltAngle.toStringAsFixed(1)),
        'analysisSize': [
          status.report!.frameSize.width,
          status.report!.frameSize.height,
        ],
      },
    };
  }

  void state(DocumentPreviewStatus previous, DocumentPreviewStatus next) {
    if (!enabled || previous.state == next.state) return;
    const immediate = {
      DocumentPreviewState.idle,
      DocumentPreviewState.error,
      DocumentPreviewState.capturing,
      DocumentPreviewState.cooldown,
    };
    final firstAnalysis = previous.report == null && next.report != null;
    if (!firstAnalysis &&
        !immediate.contains(next.state) &&
        _lastState != null &&
        _clock.elapsed - _lastState! < const Duration(milliseconds: 250)) {
      _suppressed++;
      return;
    }
    _lastState = _clock.elapsed;
    event('state', {
      'from': previous.state.name,
      ...snapshot(next),
      'coalesced': _suppressed,
    });
    _suppressed = 0;
  }

  void health(
    DocumentPreviewStatus status, {
    required bool running,
    double? nativeFps,
  }) {
    if (!enabled) return;
    final now = _clock.elapsed;
    final elapsed = (now - _lastHealth).inMicroseconds / 1e6;
    final fps = elapsed > 0 ? (reports - _lastHealthReports) / elapsed : 0.0;
    _lastHealth = now;
    _lastHealthReports = reports;
    event('health', {
      ...snapshot(status),
      'running': running,
      'receivedAnalysisFrames': received,
      'submitted': accepted,
      'skippedAtController': received - accepted,
      'reports': reports,
      'recentAnalysisFps': double.parse(fps.toStringAsFixed(2)),
      'staleReports': stale,
      'expiries': expired,
      'meanAnalysisMs': reports == 0 ? null : (_analysisMs / reports).round(),
      'maxAnalysisMs': _maxAnalysisMs.round(),
      'lastFrameAgeMs': _lastFrame == null
          ? null
          : DateTime.now().difference(_lastFrame!).inMilliseconds,
      'nativeDeliveredFps': nativeFps != null && nativeFps.isFinite
          ? nativeFps
          : null,
      'rssMiB': (ProcessInfo.currentRss / 1048576).round(),
    });
  }
}
