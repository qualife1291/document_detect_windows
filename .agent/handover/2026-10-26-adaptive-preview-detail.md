---
status: done
slug: adaptive-preview-detail
updated: 2026-10-26
---

# Handover — adaptive-preview-detail

Đã triển khai yêu cầu đã được user duyệt, commit/push main theo quyền hội thoại.
Runtime 668fffd; test fixes 66b553e/fd0894a; clock regression/source cuối b6076ff.

## Kết quả và spec

Khớp specs/adaptive-preview-detail.md: native bounded resize trước FFI,
profile 640/960/1280 tự giảm tải sampling/decode/host UI và phục hồi chậm;
cadence từ đầu sample; demand theo visibility; late-session image disposal;
crop integer inclusive không interpolation; JPEG 92 cho example và actual MP/
aspect-aware document-size/focus guidance. Không đổi detector thresholds/storage.
Backend Windows-only BSD có namespace DLL/channel/registration riêng, hashes và
license. Không private-pointer hack, dependency_overrides hoặc clear host cache.
Không có lệch scope cần duyệt thêm.

## Kiểm chứng

Windows CI 40283388912, source b6076ff9d8a07c07535fd3ee3d0e53c40b23b398:
3.32.8/3.41.9/3.47.8 đạt 116 root/11 UVC/7 example tests, 3 benchmarks,
native CTest5/8MP/bounds/pixels, endurance 60 s và release build. Stable formatter 56
files, 0 changes; host chứa cả upstream/internal plugin build+license check đạt.
Linux 3.32.8/3.41.9/3.47.7 đạt cùng Dart suites,3 benchmarks/native test và 30 s;
clock seam cuối kiểm adapter mọi SDK. Root/example source-tree hashes trùng cuối.
Regression mutation: completion-based cadence cho 7 thay vì 13 frame; code đúng 13.
Intermediate CI failures là MSVC byte fixture và test clock, không hạ assertions.
Evidence riêng giữ nguồn/SDK tại docs/progress/logs/adaptive-preview-detail/;
review docs/progress/adaptive-preview-detail.md. Historical logs không bị ghi đè.

## Tích hợp và việc ngoài task

Rebuild native một lần: example/flutter clean +pub get, chạy profile có logs.
DOC_CAPTURE_PREVIEW_PROFILE=lowResource|balanced|detail; mặc định balanced960.
Một preview/source; host await camera handoff, await stop khi route ẩn lâu.
TickerMode/inactive chỉ giảm bitmap, không dừng native producer/analysis.
Không còn việc code trong task. Physical camera clarity/focus/latency/GPU,
accessibility và 24–168h soak vẫn chưa xác nhận; product HANDOVER giữ CHUA DAT.
