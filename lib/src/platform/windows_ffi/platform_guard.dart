import 'dart:io';
import 'package:flutter/services.dart';

Future<void> verifyWindowsX64() async {
  if (!Platform.isWindows) {
    throw UnsupportedError('windows_doc_capture supports Windows x64 only');
  }
  const channel = MethodChannel('windows_doc_capture/platform');
  final architecture = await channel.invokeMethod<String>('architecture');
  if (architecture != 'x64') {
    throw UnsupportedError(
      'Windows $architecture is not supported; x64 required',
    );
  }
}
