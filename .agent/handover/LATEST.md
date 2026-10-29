---
status: done
slug: general-review
updated: 2026-10-29
---

# Handover — general-review

Direct user request review tổng quát, standing quyền fix/commit/push main, chỉ
repo document_detect_windows. Code source 2ef4de5a50c7bcd084c9901b70d69995e4bf8afb, đã push;
phần sau là docs/evidence. specs/general-review.md và docs/progress/general-review.md.

## Kết quả

Giữ root camera owner và UVC native/texture handles khi cleanup thất bại;
start/enumeration của controller cũ/mới bị chặn đến khi stop thành công. Stop khi
startup/enumeration lỗi không báo thành công giả. Dispose terminal nhưng cleanup
retry được, notifications đóng một lần; callbacks session được giải phóng.
UVC snapshot/poll/counters không chạm retained camera khi streaming=false.
Widget giữ host release đến native stop thành công, hook release idempotent;
resume xử lý pending cleanup trước acquire. Shutdown retry sau unmount; không
giữ lịch sử State sau thành công. Stop/hide báo idle, camera error giữ error,
callback throw/reentrant không phá cleanup hoặc dừng phiên mới vì lỗi đến trễ.
UVC public ID dùng Windows symbolic link normalized thay số process-local;
settings số cũ phải chọn lại. Đổi cổng USB/driver có thể đổi path. Không log path.
Diagnostics camera_cleanup_pending/error stage; disposed chỉ khi cleanup thành công.
Không thay native sampler/detector/warp/JPEG, không auto-save/global cache clear.

## Kiểm chứng

Windows CI 40813822587 (https://github.com/qualife1291/document_detect_windows/actions/runs/40813822587) success,
Flutter 3.32.8/3.41.9/3.47.8: 121 root, 16 UVC, 40 example tests/SDK; analyze,
3 benchmarks, native sampler CTest, endurance mô phỏng 60 s và release x64 build.
Stable format 60 và external host copied widget cùng camera_windows 0.2.6+4 +
original/internal UVC đạt 3 DLL/license/registration. Linux 3.32.8/3.41.9/3.47.7 đạt
root/UVC/example clean/pubget/analyze/121/16/40 tests với logs; stable configs
restored. Source/tree hashes và logs ở docs/progress/logs/general-review/.

## Giới hạn

Không build toàn app kiosk riêng, không test hardware hooks/camera thật/GPU/USB
hoặc focus/latency/24–168h. Hook cần bounded completion/failure/cancel ở host;
OS/driver treo có thể cần operator recovery. Không tuyên bố production ready;
docs/progress/HANDOVER.md vẫn CHUA DAT. Không còn code task này. Không thay saved
repository selection hoặc xử lý repo thêm nhầm.
