---
status: done
slug: adopt-agent-standard
updated: 2026-10-26
---

# Handover — adopt-agent-standard

## Kết quả

Đã review toàn bộ rule và bổ sung profile/hạ tầng phù hợp, không tự áp dụng các
approval/reset-permission gate từ tài liệu gửi kèm. Source commit b66ce7f.
Task bảo trì hoàn tất; không đổi gate production CHUA DAT của package.

## Đối chiếu đặc tả

- File: specs/adopt-agent-standard.md.
- Khớp: raw reference giữ nguyên, AGENTS/memory, env ignore, format CI, review.
- Lệch đã duyệt: không có; phạm vi profile được giao qua yêu cầu review/bổ sung.
- Lệch chưa duyệt: không có. Preview runtime ở commit a9e29c4 là task người dùng
  yêu cầu tiếp theo, specs/smooth-bitmap-preview.md, không phải scope governance.

## Đã làm

- Giữ bản gốc AGENT-CODING-STANDARD.md; profile ở docs/agent-standard-review.md.
- Thêm điểm vào, context có nguồn và hợp đồng task; rule không tự cấp quyền mới.
- Chặn env trong Git/package; giữ .env.example trackable mà không tạo file giả.
- Tool check-only kiểm cả root/adapters/example, fail closed nếu thiếu folder.
- Stable format gate sau resolve, giữ kiểm chứng SDK floor riêng.

## Chưa làm

Không còn mục trong scope task. Không claim đã áp dụng vô điều kiện raw rule.

## Cách chạy

- Sau pub get các project bằng stable: dart tool/check_format.dart.
- Analyze/typecheck: flutter analyze cho từng project.
- Windows suite/build: ./tool/verify_windows.ps1; format gate trên CI stable.

## Test sẵn có

- Trước: runtime 7d789de, CI 40262146792 đạt 108 package/6 UVC/7 example tests;
  48 Dart files format sạch trước khi thêm tool.
- Sau: CI hậu kiểm chung source a9e29c4 đạt 110 package/9 UVC/7 example tests,
  benchmark/endurance và Windows release build 3.32.8/3.41.9/3.47.8. Count tăng
  thuộc task preview; source/tool standard được kiểm cùng lượt.

## Test đã chạy

- STD-01: raw file checksum khớp; PROJECT/ARCHITECTURE/CONVENTIONS trong trần.
- STD-02: dart tool/check_format.dart — 49 files, 0 changes; CI stable cũng pass.
- STD-03: synthetic temp fixture dirty exit 1, clean exit 0, thiếu target exit 66;
  checker không ghi lại file, độc lập working directory.
- STD-04: git check-ignore --no-index kiểm 7 tên giả; env bị chặn, example không.
- STD-05: flutter analyze local pass; CI 40267546967 toàn bộ jobs success và
  Check Dart formatting on stable success.
- STD-06: review diff/pubignore và source boundaries; không đụng runtime trong b66ce7f.
- Bằng chứng: docs/progress/logs/agent-standard/ và logs/ci-provenance.json.

## Test không chạy

- Publish/audit/scanner: không thêm dependency, không publish; pubignore chỉ review
  policy. Không tuyên bố secret scan hoặc security audit toàn repository đã pass.
- Physical camera/accessibility/soak: ngoài tiêu chí governance, không có phần cứng.

## Quyết định đã ghi vào nhớ dài hạn

D-001 đến D-004 ghi platform, demand/identity, diagnostics và phạm vi evidence.
D-005 được cập nhật riêng bởi task preview tiếp theo.

## Rủi ro và nợ

SEC-05 allowed-root vẫn là chính sách caller; lock/audit đa SDK cần task release
riêng. Raw rule có điểm cần profile; không dùng nó để xóa quyền user đã cấp.
Quyền trong hội thoại hiện tại không tự chuyển sang actor/hội thoại khác.

## File đã đụng

AGENTS.md, AGENT-CODING-STANDARD.md, .agent/, specs/adopt-agent-standard.md,
docs/agent-standard-review.md, .gitignore, .pubignore, tool/check_format.dart,
.github/workflows/windows.yml và evidence trong docs/progress/logs/agent-standard/.

## Agent sau đọc gì

1. AGENTS.md và specs/adopt-agent-standard.md.
2. .agent/memory/long-term/PROJECT.md, ARCHITECTURE.md, CONVENTIONS.md, DECISIONS.md.
3. docs/agent-standard-review.md và specs/smooth-bitmap-preview.md nếu đụng preview.
