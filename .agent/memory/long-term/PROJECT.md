# Dự án

## Sản phẩm là gì

`windows_doc_capture` là Flutter package Windows x64 cho kiosk chụp giấy tờ:
preview, quad detection, quality enum/callback, manual/auto capture, perspective
crop và JPEG trong bộ nhớ hoặc thư mục do app chọn. Có example tiếng Việt.

Nguồn: README.md, docs/specification.md, lib/windows_doc_capture.dart.

## Người dùng

- Developer tích hợp API và UI trạng thái.
- Người đặt giấy trước camera kiosk; operator/IT chọn camera, mode và nơi lưu.
- QA kiểm geometry, chất lượng, lifecycle và hiệu năng trên thiết bị thật.

Nguồn: docs/specification.md mục 1.3 và example/lib/capture_app.dart.

## Ranh giới bền

- Windows x64 only. Linux là môi trường synthetic/widget test.
- A4/ID/medical/driver-like shapes là hình học, không nhận dạng ngữ nghĩa.
- Không OCR, xác minh giấy tờ, auth, backend, telemetry, mobile/web hay multi-camera.
- Một camera owner trong Dart isolate; app phải await stop/dispose trước bàn giao.
- Runtime không gọi mạng. JPEG có dữ liệu nhạy cảm; app sở hữu retention/ACL,
  encryption/upload và storage policy. Không bảo đảm secure memory erasure.
- 5/8 MP, PC yếu và 24/7 là mục tiêu cần đo thật, chưa phải lời hứa đã chứng nhận.
- Publish bị chặn bằng publish_to: none; chưa có production release.
- Gate sản phẩm còn CHUA DAT: camera/backend comparison, hardware performance,
  GPU/driver, accessibility và physical soak còn thiếu bằng chứng đầy đủ.

Nguồn: pubspec.yaml, SECURITY.md, docs/platforms.md, docs/limitations.md,
docs/continuous_operation.md, docs/progress/HANDOVER.md.
