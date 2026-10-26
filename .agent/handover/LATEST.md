---
status: done
slug: export-capture-pair
updated: 2026-10-26
---

# Handover — export-capture-pair

User đồng ý bổ sung xuất original/crop sau log 8. Feature d6b64c9, test finder
2a1644b; đã push main theo quyền hội thoại. Không có lệch scope cần duyệt thêm.

## Kết quả

Khớp specs/export-capture-pair.md: nút result-screen, native Windows folder
picker file_selector_windows 0.9.3+5 chỉ trong example. Hủy picker không ghi;
manual/auto đều dùng cùng CapturedDocument. Async copy nguyên byte JPEG vào
staging unique, flush/close cả hai rồi publish thư mục capture-<timestamp>-<suffix>
chứa original.jpg/cropped.jpg; UI hiện đường dẫn copy được. Không decode/re-encode.
Busy guard chặn duplicate/retake/Esc; late picker/unmount không ghi/cập nhật UI.
Graceful exit await write cleanup; completed pairs giữ lại; OS kill/media/cleanup
failure có thể để lại staging. Không sweep/xóa user files hoặc đổi root saveDirectory.
Logs export_pair chỉ outcome/byte counts/errorType, không path/raw exception.

## Kiểm chứng

Source 2a1644b06ca429c31a882a76dee1d59bde6fa279; Windows CI 40298617835 đạt
3.32.8/3.41.9/3.47.8:116 root, 11 UVC, 18 example tests, 3 benchmarks/native CTest,
endurance 60 s, x64 release build. Stable format 58 files, 0 changes và coexistence
host upstream/capture plugins đạt. Linux 3.32.8/3.41.9/3.47.7 đạt example pub get,
analyze/18 tests và stable format. Root/camera/adapter/tool/CI trees trùng baseline
f4e215c; Windows full suites được rerun. Test icon-button subclass finder đã sửa
cho SDK floor, không bỏ assertions; intermediate CI 40297949185 không phải proof cuối.
Evidence docs/progress/logs/export-capture-pair/, review docs/progress/export-capture-pair.md.

## Cách dùng / giới hạn

Rebuild example do thêm native plugin. Sau chụp, bấm Xuất cặp ảnh gốc + crop,
chọn folder. Hai file cùng capture để so sánh 100% trong Windows Photos. Không cần
bật crop-only save checkbox. Camera đã dừng khi xuất; không thêm preview work.
Không còn việc code trong task. Chưa thử native folder dialog thực tế/ảnh thật;
physical clarity/GPU/accessibility/24–168h soak chưa được chứng nhận. Gate CHUA_DAT.
