---
status: implemented
slug: export-capture-pair
approval_source: direct-user-request
updated: 2026-10-26
---

# Xuất cặp ảnh cùng lần chụp trong example

Nguồn: user đồng ý bổ sung thao tác xuất original/crop để kiểm tra ảnh mờ.
Quyền commit/push/merge đã cấp trong hội thoại; không thêm vòng xác nhận.

- Nút ở màn hình kết quả, hỗ trợ cả kết quả manual và auto.
- User chọn thư mục rõ ràng; hủy chọn không ghi gì. Chỉ xuất khi bấm nút.
- Lưu nguyên byte JPEG gốc/crop của cùng CapturedDocument; tên chung trong một
  thư mục con duy nhất, không ghi đè dữ liệu có sẵn. Không decode/re-encode.
- IO async, chỉ một export; không mở lại camera, chặn retake/Esc khi đang xuất;
  xử lý late completion/unmount và graceful exit. Lỗi chọn/ghi phải có UI rõ.
- Ghi staging riêng rồi publish cả thư mục sau hai file; lỗi/cancel dọn dữ liệu
  của chính lượt export, không xóa ảnh user đã lưu hoặc clear cache toàn app.
- Diagnostics safe metadata, không path/pixel/raw exception. Tính năng example,
  không đổi API package/saveDirectory hiện có/detector/crop hoặc SDK floor.

Kiểm chứng: bytes giống hệt, unique pair/no overwrite, cancel/partial IO failure,
repeated click/retake/Esc/unmount; analyzer/example tests trên SDK floor và stable,
Windows release build để kiểm folder picker. Camera thật/24h không thuộc proof CI.


## Hoàn tất

Feature d6b64c9, test finder 2a1644b. Windows run 40298617835 đạt ba SDK,
18 example tests, release build và formatter 58 files; Linux example cùng ba SDK
đạt analyze/18 tests. Source/commands/limits ở docs/progress/export-capture-pair.md
và docs/progress/logs/export-capture-pair/source.json. Product gate CHUA DAT.
