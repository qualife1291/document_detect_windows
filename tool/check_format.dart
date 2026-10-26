import 'dart:io';

/// Run with Flutter stable after resolving each project, including the optional
/// desktop adapter. Keep generated platform/build files outside this check.
Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart tool/check_format.dart');
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent;
  const targets = [
    'lib',
    'test',
    'tool',
    'example/lib',
    'example/test',
    'example/integration_test',
    'adapters/windows_doc_capture_uvc_backend/lib',
    'adapters/windows_doc_capture_uvc_backend/test',
    'adapters/windows_doc_capture_uvc/lib',
    'adapters/windows_doc_capture_uvc/test',
    'adapters/windows_doc_capture_desktop/lib',
  ];
  for (final target in targets) {
    if (!Directory.fromUri(root.uri.resolve('$target/')).existsSync()) {
      stderr.writeln('Missing format target: $target');
      exitCode = 66;
      return;
    }
  }
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['format', '--output=none', '--set-exit-if-changed', ...targets],
    workingDirectory: root.path,
    mode: ProcessStartMode.inheritStdio,
  );
  exitCode = await process.exitCode;
}
