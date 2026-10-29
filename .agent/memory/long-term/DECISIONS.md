# Quyết định

## D-001 — Runtime Windows x64, graph theo SDK

- Ngày: 2026-10-26
- Trạng thái: accepted
- Lý do: docs/specification.md và pubspec của từng package yêu cầu sàn 3.32.8.
- Hệ quả: desktop adapter Dart 3.11 là optional; Linux test không xác nhận runtime.
- Nguồn: docs/platforms.md, pubspec.yaml, adapters/*/pubspec.yaml.

## D-002 — Giữ bounded bitmap fallback và stream identity

- Ngày: 2026-10-26
- Trạng thái: accepted
- Lý do: GPU log và regression nhấp nháy đã được tái hiện ở source trước.
- Hệ quả: root default texture, example bitmap; không queue frame hoặc reset ảnh
  mỗi report. Giữ cache eviction riêng và camera stop trước result.
- Nguồn: docs/progress/GPU_LOG_REVIEW.md, FOURTH_LOG_REVIEW.md và source 7d789de.

## D-003 — Diagnostics không được giữ dữ liệu giấy tờ

- Ngày: 2026-10-26
- Trạng thái: accepted
- Lý do: người dùng yêu cầu debugPrint cho test thực tế; JPEG có dữ liệu nhạy cảm.
- Hệ quả: chỉ safe metadata, debug/opt-in profile-release, sink lỗi không cản cleanup.
- Nguồn: SECURITY.md, README.md và test/diagnostics_test.dart.

## D-004 — Bằng chứng task và readiness sản phẩm là hai phạm vi

- Ngày: 2026-10-26
- Trạng thái: accepted
- Lý do: CI không có camera/driver, accessibility inspection hoặc physical soak.
- Hệ quả: ghi source/SDK/lệnh thật; task hạ tầng done không đổi gate CHUA DAT.
- Nguồn: docs/progress/HANDOVER.md, docs/continuous_operation.md.

## D-005 — Preview cadence độc lập, demand trước readback

- Ngày: 2026-10-26
- Trạng thái: accepted
- Lý do: log 5 native ~30 FPS nhưng preview đi chung analysis 5 FPS.
- Hệ quả: target bitmap ~15, analysis giữ gate; chia sẻ readback, pause capture và
  decoder demand/backoff; offered FPS không thay measured display FPS.
- Nguồn: specs/smooth-bitmap-preview.md và docs/progress/fifth-log-review.md.

## D-006 — Native bounded sampling, adaptive preview theo host UI

- Ngày: 2026-10-26; trạng thái: accepted.
- Lý do: log6 preview640/~9 FPS dù target15; user duyệt tối ưu cả app tích hợp.
- Hệ quả: fork Windows-only BSD có provenance, DLL/channel/registration riêng;
  nearest analysis640, bilinear preview640/960/1280 trước FFI. Snapshot vẫn full.
  Chi phí sampling/decode/UI điều tiết preview; route dài hạn cần caller await stop.
  Không giành camera của host, dependency_overrides hoặc clear cache toàn app.
- Nguồn: specs/adaptive-preview-detail.md, docs/integration-performance.md.

## D-007 — Xuất cặp JPEG chủ động trong example

- Ngày: 2026-10-26; trạng thái: accepted.
- Lý do: user cần cặp ảnh cùng capture để phân biệt mờ camera/crop.
- Hệ quả: chỉ bấm export mới chọn thư mục/ghi original + cropped nguyên byte;
  staging riêng, một operation, cancel/cleanup và không mở lại camera. Native
  folder picker pin SDK-compatible trong example; root/storage mặc định không đổi.
- Nguồn: specs/export-capture-pair.md và example/lib/capture_pair_exporter.dart.

## D-008 — Kiosk capture mặc định trong bộ nhớ, dừng khi ẩn

- Ngày: 2026-10-26; trạng thái: accepted.
- Lý do: user yêu cầu review kiosk và không lưu file khi chụp.
- Hệ quả: example bỏ auto-save, giữ export pair chủ động phục vụ test. Dùng UVC
  không saveDirectory; root opt-in API vẫn tương thích, desktop temp file không
  đáp ứng no-capture-files. Hidden/paused/detached stop, epoch hủy late operations,
  foreground restart thủ công; inactive không giành/nhả camera do mất focus.
- Nguồn: specs/kiosk-memory-review.md, docs/progress/kiosk-memory-review.md.

## D-009 — Widget tích hợp chung có single/batch riêng

- Ngày: 2026-10-28; trạng thái: accepted.
- Lý do: user gửi widget dùng CameraPlatform, flow ID/review và upload nhiều ảnh.
- Hệ quả: sample copyable ngoài root API, không thêm GetX dependency. Giữ
  capture()/bytes, mặc định batch giống widget cũ; ID chọn single dừng trước
  callback. Batch giữ session/removal latch, không giữ ảnh; app sở hữu history.
  Hardware/control và camera-ID mapping là hook; không giả định service/ROI cũ
  dùng được qua backend khác. Host vẫn điều phối camera_windows/UVC bằng await.
- Nguồn: specs/kiosk-preview-integration.md, docs/integration/kiosk-getx.md.
