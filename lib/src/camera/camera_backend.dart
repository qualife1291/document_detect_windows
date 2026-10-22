import 'frame_source.dart';

/// No default until the two candidate backends have measured Windows evidence.
/// Pass the selected adapter explicitly to WindowsDocCapture(frameSource: ...).
class CameraBackend {
  static FrameSource requireSelected(FrameSource? source) {
    if (source == null) {
      throw StateError(
        'Select a measured Windows FrameSource adapter. See README.',
      );
    }
    return source;
  }
}
