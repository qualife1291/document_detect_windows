# Platform policy

Only **Windows x64** is an intended runtime platform. Linux may run synthetic
Dart/widget tests; that does not establish Linux camera support.

| Platform | Runtime checks | Not established automatically |
| --- | --- | --- |
| Windows x64 | OS + native plugin architecture; camera enumeration/open/start errors; UVC stream error and stalled-sequence handling | Native compilation, driver correctness, policy reason, physical orientation, real frame latency, CPU and UI accessibility require Windows evidence |
| Windows ARM64 / x86 | Rejected by the native architecture guard | Not supported even when a dependency can compile there |
| Linux, macOS, Android, iOS, Web | Production capture rejects non-Windows; only Windows plugin registration is declared | Not supported |

The pure Dart fallback resolves at Dart 3.8.0 and the chosen example adapter at
3.8.1; the Flutter floor remains 3.32.8. The optional desktop adapter's Dart 3.11
requirement never enters the floor package/example dependency graph.
