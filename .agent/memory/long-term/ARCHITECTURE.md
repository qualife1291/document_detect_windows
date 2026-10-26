# Kiến trúc

## Stack

- Root: Flutter >=3.32.8, Dart >=3.8.0 <4; image 4.5.4; flutter_lints ^5.0.0.
- UVC adapter/example/backend: Dart >=3.8.1; internal Windows-only BSD derivative
  of flutter_ffi_uvc 1.1.2, source hashes/license under adapters/windows_doc_capture_uvc_backend.
- Desktop adapter tùy chọn: Flutter >=3.41.9/Dart >=3.11;
  camera_desktop 2.0.0, camera_platform_interface ^2.7.0, image 4.5.4.
- Windows CI: 3.32.8, 3.41.9, stable tại thời điểm chạy; đọc version log thật,
  không giả định stable luôn bằng SDK đã cài trong cloud.

Nguồn: năm pubspec.yaml và .github/workflows/windows.yml.

## Thư mục

| Đường dẫn | Vai trò |
| --- | --- |
| lib/src/camera | Controller, FrameSource abstraction, lease, operation queue |
| lib/src/detection | Pure-Dart detector, chất lượng, analyzer isolate |
| lib/src/capture | Auto state machine, worker cancellation, warp/JPEG/save |
| lib/src/preview | Enum/status, overlay geometry và bounded bitmap preview |
| lib/src/diagnostics | JSON metadata/redaction/health, không pixel |
| adapters | UVC + backend Windows nội bộ; desktop tùy chọn tách graph |
| example | Windows runner, kiosk UI, camera/result ownership |
| test | Fixtures synthetic, regression và lifecycle/conditions |
| tool | Bootstrap, validation, benchmark, synthetic endurance, format check |
| docs/progress | Bằng chứng theo source/SDK; HANDOVER là gate sản phẩm |
| .agent, specs | Nhớ/handover agent và hợp đồng từng task |

## Dữ liệu chạy thế nào

FrameSource mở một camera. Root API default texture; example chọn UVC bitmap
profile 640/960/1280 (không upscale). Stream identity ổn định; một decode,
bỏ frame khi bận. Balanced mặc định 960; tải cao giảm về 640.
Analysis demand và bitmap demand tách nhau; example target preview ~15 FPS còn
analysis ~5 FPS. Một native lock cung cấp hai output bounded khi cùng due; thu nhỏ trước FFI.
Decoder busy/unmount/inactive/TickerMode(false)/capture không kéo thêm preview.
Sampling/decode/host frame costs giảm size/cadence, phục hồi 10 s mỗi mức. Native
producer vẫn xử lý full stream; không bảo đảm tổng CPU. Health tách offers/native/analysis.
Analyzer isolate nhận frame ≤640 px, trả quad/quality; controller phát trạng thái
và enum, expire geometry cũ. Auto cần ổn định và feedback, không chỉ enum clear.

Snapshot lấy full negotiated stream, detect lại, rồi worker cancellable warp và
encode JPEG. Crop thẳng integer copy inclusive pixels; không snap quad lệch.
Package JPEG 90, example 92 theo benchmark chữ giả lập. Crop padding mặc định .02; quad detect khác cropQuad dùng để warp.
Controller giới hạn một capture worker; session cũ không được trả kết quả.
Save tạo file .part exclusive, flush, rename JPEG; caller chọn nơi lưu/retention.

Example high preset độc lập sampling 200 ms; có medium/high/veryHigh. Stop camera
trước result, retake mở lại. Result decode ≤1280 px, scaleDown theo DPI, evict
provider riêng; không sửa byte JPEG hoặc clear toàn bộ image cache.
Result có export pair chủ động: file_selector_windows 0.9.3+5 (example-only)
chọn thư mục; async ghi nguyên byte original/cropped trong staging riêng rồi
publish thư mục con unique. Busy chặn double-click/retake; exit await write cleanup.
Không đổi crop-only saveDirectory của package; file đã publish thuộc caller.

Nguồn: camera_controller.dart, quality_analyzer.dart, crop_pipeline.dart,
frame_source.dart, UVC adapter và example/lib/.

## Lệnh

Dùng Flutter tương ứng trên PATH. Chạy từ root trừ khi ghi khác.

| Việc | Lệnh |
| --- | --- |
| Cài root | flutter pub get |
| Cài adapter/example | flutter pub get trong từng project |
| Format check (stable, sau pub get các project) | dart tool/check_format.dart |
| Format file thay đổi | dart format <đường-dẫn-file.dart> |
| Analyze/typecheck root | flutter analyze |
| Test root | flutter test --reporter expanded |
| Adapter UVC | flutter analyze và flutter test trong adapters/windows_doc_capture_uvc |
| Example | flutter analyze và flutter test trong example |
| Desktop tùy chọn, SDK đủ | flutter pub get và flutter analyze trong adapters/windows_doc_capture_desktop |
| Chạy Windows | flutter run -d windows trong example |
| Build Windows | flutter build windows --release trong example |
| Kiểm Windows đầy đủ | ./tool/verify_windows.ps1 |
| Camera thật có operator | ./tool/verify_windows.ps1 -RealCamera -EnforceKioskFps |
| Linux supplemental | FLUTTER_BIN=<sdk>/bin/flutter SDK_LABEL=<version> bash tool/validate_linux.sh |
| Bootstrap cloud Linux | bash tool/bootstrap_cloud.sh |

Bootstrap hiện pin ba SDK Linux; CI stable có thể mới hơn. Root analyzer exclude
adapters/example nên analyze root không thay thế kiểm tra riêng. Format gate chạy
stable sau khi resolve tất cả project vì desktop adapter cần Dart 3.11.
