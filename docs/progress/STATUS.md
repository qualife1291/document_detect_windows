# Trạng thái triển khai

Cập nhật: 2026-10-22 (Asia/Saigon). Đây là tiến độ nội bộ; chưa handover.

| Phase | Platform bắt buộc | Trạng thái | Bằng chứng / phần còn thiếu |
| --- | --- | --- | --- |
| 1 — Skeleton & camera preview | Windows x64 | Đang làm | Có native architecture guard, FrameSource và hai adapter; chưa build/preview/đo latency trên Windows |
| 2 — Detection & quality | Windows x64 | Đang làm | Có grayscale/Gaussian/Canny/contour/quad, quality isolate và synthetic tests; cần benchmark kiosk Windows |
| 3 — Warning & auto-capture | Windows x64 | Đang làm | Có warning, kiểm tra chuyển động, feedback ≥500 ms, cooldown và callback tests; cần camera thật |
| 4 — Crop & output | Windows x64 | Đang làm | Có homography, snapshot mới, kiểm tra chuyển động lại, JPEG/file tests; cần 4K/DPI/camera Windows |
| 5 — Hardening & handover | Windows x64 | Đang làm | Có SDK matrix automation và tài liệu; còn toàn bộ chứng cứ Windows/accessibility/backend comparison |

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
`docs/progress/logs/linux-*/`. Không suy ra native Windows build/runtime từ đó.
Tên `windows_doc_capture` trả HTTP 404 khi kiểm tra pub.dev API ngày 2026-10-22;
chưa đăng ký/publish tên. Kho GitHub ban đầu chưa có commit/ref và được triển
khai từ đầu theo đặc tả người dùng cung cấp.
