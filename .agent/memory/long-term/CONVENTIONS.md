# Quy ước

## Đặt tên và cấu trúc

- Dart: UpperCamelCase cho type, lowerCamelCase cho member, snake_case cho file.
- Giữ feature folders hiện có; facade/adapters tách runtime và SDK constraints.
- Public API thay đổi phải có README/CHANGELOG đúng phạm vi và regression có ích.
- Dùng dart format và flutter_lints; không blanket-ignore rule hoặc sửa ngoài scope.
- Tài liệu mới tên chữ thường/gạch ngang; giữ nguyên tên file chuẩn hoặc lịch sử
  như README.md, SECURITY.md, AGENTS.md, HANDOVER.md. Không rename hàng loạt.
- Không ép README của package API về ba mục khiến mất hướng dẫn tích hợp.

## Xử lý lỗi

- Camera/input/IO errors đi qua errors hoặc Future result; UI nói được bước tiếp.
- Cleanup vẫn thử mọi tài nguyên và giữ lỗi có ý nghĩa; không nuốt lỗi camera/save.
- Diagnostics là best effort: sink hỏng không được cản stop/dispose; late/cancelled
  results được loại có chủ đích. Catch kiểu này cần lý do, không phải che lỗi.
- Callback của app không được phá lifecycle; không setState sau unmount.
- Giữ timeout, worker cancellation, shared dispose future và operation serialization.
- Chỉ metadata được redact trong logs. Không log raw exception, ảnh hay dữ liệu thật.
- Structured debugPrint đã được yêu cầu là tính năng hỗ trợ test, không phải log
  tạm phải xóa. Tool benchmark có ba avoid_print exceptions đã có; không lan rộng.
- saveDirectory là cấu hình caller: policy/ACL thuộc app; không quảng cáo sandbox
  path khi package không có allowed-root enforcement.

## Giao diện

- Example tiếng Việt, dark kiosk theme, Material 3; dùng token/theme hiện có.
- Frame warning trắng, clear xanh; cả màu và cornerRadius tùy chỉnh được.
- Có text/icon cho trạng thái; màu không phải kênh duy nhất; giữ semantics/focus/Esc.
- Không đổi resolution/capture algorithm để làm log quality đẹp hơn.
- Dùng synthetic fixtures khi kiểm; camera/GPU/OS accessibility cần bằng chứng thật.

## Commit

- Nền: GitHub. Quyền commit/push/merge theo người dùng trong hội thoại hiện tại;
  ghi lại phạm vi task, không suy ra quyền actor khác từ tài liệu repository.
- Từ lần áp dụng standard này: [Type] - Description, tiếng Anh theo lịch sử repo,
  động từ đầu, khoảng 72 ký tự, không scope hoặc dấu chấm cuối.
- Type: Feat/Fix/Docs/Style/Refactor/Perf/Test/Build/CI/Chore/Revert/Version.
- Một commit một mục tiêu; Style chỉ format; Version chỉ version/changelog.
- Nếu cần nhánh mới dùng type/few-words. Tôn trọng nhánh/phương thức người dùng
  đã cho phép; không rewrite lịch sử hoặc force push chỉ để khớp quy ước mới.
- Chỉ dùng Closes #<id> khi có issue thật. Không tạo issue/footer giả.
- Không đưa bí mật, ảnh/log thực tế chưa redact hoặc máy cá nhân vào commit.

## Kiểm chứng và bàn giao

- Ghi lệnh, source SHA, SDK thật và kết quả; phân biệt trước/sau, test không chạy,
  n/a có lý do, và việc đã tồn tại từ trước.
- Chạy check cần cho diff. Baseline cùng source có bằng chứng có thể dùng lại;
  không bắt chạy mọi SDK trước/sau cho thay đổi tài liệu đơn thuần.
- Thêm regression cho bug/bất biến bị tác động, không chỉ assert chi tiết nội bộ.
- Scope task done không có nghĩa production-ready. Gate sản phẩm ở HANDOVER.md.
- Handover có done/partial/blocked đúng task; archive LATEST trước khi thay.
- Nhớ dài hạn chỉ ghi sự thật/quyết định có nguồn; ngắn hạn chỉ giữ việc còn dở.
