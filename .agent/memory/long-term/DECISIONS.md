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
