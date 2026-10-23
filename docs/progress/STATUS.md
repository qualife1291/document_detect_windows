# Trạng thái triển khai

Cập nhật: 2026-10-23 (Asia/Saigon). Đây là tiến độ nội bộ; chưa handover.

| Phase | Platform bắt buộc | Trạng thái | Bằng chứng / phần còn thiếu |
| --- | --- | --- | --- |
| 1 — Skeleton & camera preview | Windows x64 | Đang làm | Có native architecture guard, FrameSource và hai adapter; đã build Windows trên ba SDK, còn preview camera thật/latency |
| 2 — Detection & quality | Windows x64 | Đang làm | Có grayscale/Gaussian/Canny/contour/quad, quality isolate và synthetic tests; đã benchmark synthetic Windows CI, còn benchmark kiosk target |
| 3 — Warning & auto-capture | Windows x64 | Đang làm | Có callback enum preview, overlay 4 góc contain/cover, expiry, kiểm tra chuyển động, feedback ≥500 ms và cooldown; cần camera thật |
| 4 — Crop & output | Windows x64 | Đang làm | Có homography, snapshot mới, kiểm tra chuyển động lại, JPEG/file tests; cần 4K/DPI/camera Windows |
| 5 — Hardening & handover | Windows x64 | Đang làm | Có Windows SDK build/test logs và tài liệu; còn camera thật/accessibility/backend comparison |

## Hai candidate camera

| Candidate | Metadata đã kiểm tra qua pub.dev | Đo latency / độ ổn định Windows | Quyết định |
| --- | --- | --- | --- |
| camera_desktop 2.0.0 | Yêu cầu Dart ^3.11.0; không resolve trên sàn 3.8.1 | Chưa làm | Adapter tùy chọn, tách dependency graph; chưa chọn default |
| flutter_ffi_uvc 1.1.2 | Dart ^3.8.1; Media Foundation + native Texture, API copy frame | Chưa làm | Example chọn rõ candidate thử nghiệm; chưa chọn default |

Không có số đo camera-to-texture, CPU/driver hoặc chứng cứ Windows để chọn
backend production. Dependency candidate chỉ nằm trong package adapter riêng.
`dartcv4` chưa tích hợp; facade dùng pure Dart trên mọi SDK hiện tại.

## Phạm vi kiểm chứng

Máy cloud là Linux x86_64. Bằng chứng supplemental nằm trong
`docs/progress/logs/linux-*/`. Native build/test có bằng chứng riêng từ Windows
GitHub Actions; không suy ra camera runtime từ synthetic tests.
Tên `windows_doc_capture` trả HTTP 404 khi kiểm tra pub.dev API ngày 2026-10-22;
chưa đăng ký/publish tên. Kho GitHub ban đầu chưa có commit/ref và được triển
khai từ đầu theo đặc tả người dùng cung cấp.

## Cập nhật preview — 2026-10-23

Đã triển khai DocumentPreviewState / onDocumentStateChanged, previewStatus và
overlay bốn góc trong API dùng chung. Detection vẫn chạy khi tắt auto-capture.
Có kiểm thử ảnh synthetic cho quality enums, geometry khi letterbox/crop/4K,
callback dedup, capture lifecycle, restart/error và xóa marker quá hạn.
Kiểm tra SDK/Windows cho thay đổi này đang được chạy; camera thật và
accessibility gates vẫn chưa hoàn thành.
