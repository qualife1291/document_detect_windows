/// Document capture for Windows x64 only. Backend selection is explicit.
library;

export 'src/camera/camera_controller.dart';
export 'src/camera/frame_source.dart';
export 'src/detection/document_detector.dart';
export 'src/detection/detection_result.dart';
export 'src/detection/detector_facade.dart';
export 'src/detection/quality_analyzer.dart';
export 'src/capture/auto_capture_controller.dart';
export 'src/capture/captured_document.dart';
export 'src/capture/crop_pipeline.dart';
export 'src/warnings/preview_warning.dart';

export 'src/preview/document_preview_status.dart';
export 'src/preview/document_camera_preview.dart';

export 'src/capture/capture_cancellation.dart' show CaptureCancellation;

export 'src/capture/document_image_filter.dart' show DocumentImageFilter;

export 'src/preview/rgba_camera_preview.dart';
