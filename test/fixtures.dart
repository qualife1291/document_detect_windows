import 'dart:typed_data';
import 'dart:ui';
import 'package:windows_doc_capture/windows_doc_capture.dart';
import 'package:windows_doc_capture/src/detection/geometry.dart';

FrameBuffer fixture({
  int width = 320,
  int height = 240,
  List<Offset>? quad,
  int paper = 190,
  int background = 35,
  bool texture = true,
  bool document = true,
  int sequence = 1,
}) {
  final q =
      quad ??
      [
        Offset(width * .18, height * .18),
        Offset(width * .82, height * .18),
        Offset(width * .82, height * .82),
        Offset(width * .18, height * .82),
      ];
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final inside = document && insideQuad(x.toDouble(), y.toDouble(), q);
      final line = texture && inside && x % 13 < 2 && y % 11 < 4;
      final value = inside ? (line ? paper - 65 : paper) : background;
      final i = (y * width + x) * 4;
      bytes[i] = value;
      bytes[i + 1] = value;
      bytes[i + 2] = value;
      bytes[i + 3] = 255;
    }
  }
  return FrameBuffer(
    width: width,
    height: height,
    rgba: bytes,
    capturedAt: DateTime.now(),
    sequence: sequence,
  );
}

DetectionResult good({List<Offset>? quad}) => DetectionResult(
  hasDocument: true,
  quad:
      quad ??
      const [
        Offset(20, 20),
        Offset(180, 20),
        Offset(180, 120),
        Offset(20, 120),
      ],
  coverageRatio: .5,
  edgeMargin: .1,
  tiltAngle: 0,
  blurScore: 300,
  brightnessScore: .6,
);
const normalized = [
  Offset(.1, .1),
  Offset(.9, .1),
  Offset(.9, .8),
  Offset(.1, .8),
];
