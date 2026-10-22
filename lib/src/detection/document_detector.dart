import '../camera/frame_source.dart';
import 'detection_result.dart';

abstract class DocumentDetector {
  Future<DetectionResult> detect(FrameBuffer frame);
  void dispose();
}
