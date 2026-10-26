import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'package:windows_doc_capture_uvc/windows_doc_capture_uvc.dart';
import 'capture_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const lowResource = bool.fromEnvironment(
    'DOC_CAPTURE_LOW_RESOURCE',
    defaultValue: true,
  );
  const safePreview = bool.fromEnvironment(
    'DOC_CAPTURE_SAFE_PREVIEW',
    defaultValue: true,
  );
  const requestedPreviewFps = int.fromEnvironment(
    'DOC_CAPTURE_PREVIEW_FPS',
    defaultValue: 15,
  );
  final previewFps = requestedPreviewFps.clamp(5, 20);
  final previewInterval = Duration(microseconds: 1000000 ~/ previewFps);
  final interval = Duration(milliseconds: lowResource ? 200 : 100);
  debugPrint(
    '[capture_example] ${jsonEncode({'v': 1, 'time': DateTime.now().toUtc().toIso8601String(), 'event': 'configuration', 'lowResource': lowResource, 'safePreview': safePreview, 'analysisIntervalMs': interval.inMilliseconds, 'preset': ResolutionPreset.high.name, 'bitmapTargetFps': previewFps})}',
  );
  runApp(
    CaptureApp(
      preset: ResolutionPreset.high,
      capture: WindowsDocCapture(
        analysisInterval: interval,
        frameSource: UvcFrameSource(
          pollInterval: interval,
          bitmapPreviewInterval: previewInterval,
          preferredNativeFps: lowResource ? 15 : 30,
          previewMode: safePreview
              ? UvcPreviewMode.bitmap
              : UvcPreviewMode.texture,
        ),
      ),
    ),
  );
}
