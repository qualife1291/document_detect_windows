# Compile a host with BOTH plugins without opening physical devices.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path $env:TEMP "doc-capture-coexistence-$PID"
$logs = Join-Path $repo 'docs/progress/logs/windows-coexistence'
New-Item -ItemType Directory -Force $fixture, $logs | Out-Null
$log = Join-Path $logs 'build.txt'
function Run-Checked([string[]]$arguments) {
  & flutter @arguments 2>&1 | Tee-Object -FilePath $log -Append
  if ($LASTEXITCODE -ne 0) { throw "Coexistence check failed: flutter $arguments" }
}
Push-Location $fixture
try {
  Run-Checked @('create', '--no-pub', '--platforms=windows', '--project-name=doc_capture_coexistence', '.')
  $rootPath = $repo.Replace('\', '/').Replace("'", "''")
  @"
name: doc_capture_coexistence
publish_to: none
environment:
  sdk: '>=3.8.1 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  flutter_ffi_uvc: 1.1.2
  windows_doc_capture_uvc:
    path: '$rootPath/adapters/windows_doc_capture_uvc'
"@ | Set-Content pubspec.yaml
  @'
import 'package:flutter/widgets.dart';
import 'package:flutter_ffi_uvc/flutter_ffi_uvc.dart';
import 'package:windows_doc_capture_uvc/windows_doc_capture_uvc.dart';
void main() {
  final source = UvcFrameSource(previewMode: UvcPreviewMode.bitmap);
  final upstream = UvcCamera(); // lazy: no native device opened
  runApp(Directionality(textDirection: TextDirection.ltr,
    child: Text('${source.runtimeType} / ${upstream.runtimeType}')));
}
'@ | Set-Content lib/main.dart
  Run-Checked @('pub', 'get')
  Run-Checked @('build', 'windows', '--release')
  $release = 'build/windows/x64/runner/Release'
  foreach ($name in @('flutter_ffi_uvc_plugin.dll', 'windows_doc_capture_uvc_backend_plugin.dll', 'LICENSE.windows_doc_capture_uvc_backend')) {
    if (-not (Test-Path (Join-Path $release $name))) { throw "Missing separate bundled file: $name" }
  }
  $registration = Get-Content windows/flutter/generated_plugin_registrant.cc -Raw
  foreach ($name in @('FlutterFfiUvcPluginCApiRegisterWithRegistrar', 'WindowsDocCaptureUvcBackendPluginCApiRegisterWithRegistrar')) {
    if (-not $registration.Contains($name)) { throw "Missing independent registration: $name" }
  }
  'COEXISTENCE PASS: both DLLs, license and independent registration; no camera opened.' | Tee-Object -FilePath $log -Append
} finally {
  Pop-Location
  Remove-Item -Recurse -Force $fixture -ErrorAction SilentlyContinue
}
