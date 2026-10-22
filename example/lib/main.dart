import 'package:flutter/material.dart';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'package:windows_doc_capture_uvc/windows_doc_capture_uvc.dart';
import 'capture_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CaptureApp(capture: WindowsDocCapture(frameSource: UvcFrameSource())));
}
