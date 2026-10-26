param([switch]$RealCamera, [switch]$EnforceKioskFps)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logs = Join-Path $repo "docs/progress/logs/windows-$stamp"
New-Item -ItemType Directory -Force $logs | Out-Null
function Run-Flutter([string]$name, [string[]]$arguments) {
  & flutter @arguments 2>&1 | Tee-Object -FilePath (Join-Path $logs "$name.txt")
  if ($LASTEXITCODE -ne 0) { throw "flutter $arguments failed: $LASTEXITCODE" }
}
Push-Location $repo
try {
  Run-Flutter 'version' @('--version')
  Run-Flutter 'doctor' @('doctor', '-v')
  Run-Flutter 'package-pub-get' @('pub', 'get')
  Run-Flutter 'package-analyze' @('analyze')
  Run-Flutter 'package-tests' @('test', '--reporter', 'expanded')
  $benchmark = @('test', 'tool/detection_benchmark.dart', '--reporter', 'expanded')
  if ($EnforceKioskFps) { $benchmark += '--dart-define=ENFORCE_TARGET_FPS=true' }
  Run-Flutter 'detection-benchmark' $benchmark
  Run-Flutter 'jpeg-benchmark' @('test', 'tool/jpeg_quality_benchmark.dart', '--reporter', 'expanded')
  Run-Flutter 'processing-benchmark' @('test', 'tool/scan_processing_benchmark.dart', '--reporter', 'expanded')
  Run-Flutter 'endurance' @('test', 'tool/endurance_test.dart', '--dart-define=SOAK_SECONDS=60', '--reporter', 'expanded')
  Push-Location (Join-Path $repo 'adapters/windows_doc_capture_uvc_backend')
  try {
    Run-Flutter 'backend-pub-get' @('pub', 'get')
    Run-Flutter 'backend-analyze' @('analyze')
    $nativeBuild = Join-Path $env:TEMP "doc-capture-sampler-$PID"
    try {
      & cmake -S test/native -B $nativeBuild -A x64 2>&1 | Tee-Object -FilePath (Join-Path $logs 'native-configure.txt')
      if ($LASTEXITCODE -ne 0) { throw 'Native test configure failed' }
      & cmake --build $nativeBuild --config Release 2>&1 | Tee-Object -FilePath (Join-Path $logs 'native-build.txt')
      if ($LASTEXITCODE -ne 0) { throw 'Native test build failed' }
      & ctest --test-dir $nativeBuild -C Release -V 2>&1 | Tee-Object -FilePath (Join-Path $logs 'native-tests.txt')
      if ($LASTEXITCODE -ne 0) { throw 'Native tests failed' }
    } finally { Remove-Item -Recurse -Force $nativeBuild -ErrorAction SilentlyContinue }
  } finally { Pop-Location }
  Push-Location (Join-Path $repo 'adapters/windows_doc_capture_uvc')
  try {
    Run-Flutter 'uvc-pub-get' @('pub', 'get')
    Run-Flutter 'uvc-analyze' @('analyze')
    Run-Flutter 'uvc-tests' @('test', '--reporter', 'expanded')
  } finally { Pop-Location }
  Push-Location (Join-Path $repo 'example')
  try {
    Run-Flutter 'example-pub-get' @('pub', 'get')
    Run-Flutter 'example-analyze' @('analyze')
    Run-Flutter 'example-tests' @('test', '--reporter', 'expanded')
    Run-Flutter 'example-build' @('build', 'windows', '--release')
    if ($RealCamera) {
      Run-Flutter 'real-camera-integration' @('test', 'integration_test/real_camera_test.dart', '-d', 'windows')
    }
  } finally { Pop-Location }
  Write-Output "Logs: $logs. Physical-camera, latency, CPU and accessibility gates still require operator evidence."
} finally { Pop-Location }
