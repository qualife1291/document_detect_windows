---
status: done
slug: kiosk-memory-review
updated: 2026-10-26
---

# Handover — kiosk-memory-review

User yêu cầu review package/kiosk, không lưu file khi chụp, commit/push mọi file
liên quan. Source 05355304ed3974677c225bdddb04f9abec5ccb3a đã push main.
Phạm vi specs/kiosk-memory-review.md hoàn tất; phần sau chỉ documentation/evidence.

## Kết quả

Example bỏ save checkbox/directory, không truyền saveDirectory: manual/auto JPEG
trong RAM. Giữ nút export pair chủ động phục vụ test; xuất vẫn tạo file theo yêu
cầu, không xóa ảnh đã xuất. Root API saveDirectory opt-in giữ tương thích.
UVC snapshot/worker không tạo temporary image; camera_desktop dependency có temp
file nên không dùng khi cần no-capture-files. OS paging/secure erasure ngoài scope.
Hidden/paused/detached stop native/analysis và cancel pending capture/start;
operation epoch chặn late result/export kể cả hide rồi resume. Inactive focus/
native picker không stop. Foreground restart thủ công sau cleanup; chặn concurrent
UI/enumeration. Host route/tab hiding vẫn cần awaited stop/dispose trước handoff.
Bounded frames/one decoder/cancellation/owned cache eviction không đổi. Sửa stale
màu cam/save-error và docs còn nói full RGBA/Dart downsampling.

## Kiểm chứng

Windows CI 40311068502 source 0535530 success, Flutter 3.32.8/3.41.9/3.47.8:
117 root, 11 UVC, 22 example tests; analyze tất cả, 3 benchmarks,native CTest,
synthetic endurance 60 s và release build. Stable format 58 và host coexistence đạt.
Linux 3.32.8/3.41.9 logs root/example analyze 117/22; stable 3.47.7 tương tự trong
transcript trước SDK switching, đã restore configs/format. Evidence/source hashes:
docs/progress/logs/kiosk-memory-review/. Review docs/progress/kiosk-memory-review.md.
Lifecycle harness dùng transition hợp lệ, real-async start gate và cleanup gate
một operation; không hạ assertions hay bỏ test. API runtime root chỉ thêm docs;
adapters/tool/CI trees không đổi so với 6e7929b.

## Giới hạn / việc sau

Hai cặp ảnh thật đã review ngoài repo: text mềm từ original 720p, crop thêm nhẹ;
cặp 1 có dải đen che mép ngay original. Chưa đổi threshold/warp filter: cần fixture
đa loại và CPU/calibration trước. Không commit ảnh/log thật. Physical camera/GPU/
USB/accessibility/24–168h soak vẫn thiếu. Product gate CHUA DAT. Không còn việc
code task này; tích hợp dùng UVC không saveDirectory, một camera owner/preview và
awaited cleanup. Kiosk cấm export thì không đưa nút diagnostic vào UI sản phẩm.
