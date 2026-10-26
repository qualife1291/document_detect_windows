---
status: approved
slug: adopt-agent-standard
level: maintenance
updated: 2026-10-26
approved: 2026-10-26
approval_source: direct-user-request
source_idea: |
  Có rule này mới, đọc qua, review và bổ sung các phần chưa có hoặc thấy hợp lý.
---

# Tiếp nhận coding standard cho repository

## Nguồn và phạm vi

Người dùng yêu cầu thực hiện trực tiếp review và bổ sung phần phù hợp. Đây là
ủy quyền cho task bảo trì này, không phải khẳng định họ đã đọc/duyệt từng dòng
profile hoặc cho phép thay mọi hành vi sản phẩm. Quyền commit/push/merge đã được
cấp trong cùng hội thoại trước task. Raw rule là đầu vào review, không tự thi hành.

Baseline: tài liệu be7bdfe, runtime 7d789de, Windows CI 40262146792.
Nguồn repo: README, SECURITY, pubspec/lint của bốn project, CI, tests và handover.

## Việc

- Giữ nguyên tài liệu gửi lên tại AGENT-CODING-STANDARD.md để đối chiếu.
- Thêm AGENTS, nhớ dài/ngắn hạn và bàn giao có nguồn, gọn, không dữ liệu riêng tư.
- Viết docs/agent-standard-review.md nêu phần đã có, phần thêm và phần điều chỉnh.
- Thêm ignore cho .env/.env.* với ngoại lệ .env.example.
- Thêm cross-platform Dart format checker và stable-only CI gate sau pub get.
- Loại agent metadata/spec khỏi package archive dù publish hiện bị chặn.

## Không đụng

- Camera, image pipeline, public API, quality thresholds hoặc UI design.
- SDK floor, dependency versions, lockfile policy đa SDK, schema/auth/storage policy.
- Spec sản phẩm cũ, evidence lịch sử hoặc gate production còn thiếu bằng chứng.

## Dữ liệu, platform và design

Không tạo/lưu ảnh giấy tờ, không đọc .env/key thật. Runtime vẫn Windows x64;
Linux chỉ kiểm source/synthetic. Task thêm tài liệu/developer tooling, không đổi UI.
Biến môi trường sản phẩm không đổi; các DOC_CAPTURE_* hiện là dart-define,
không cần tạo .env.example rỗng cho một cơ chế app không đọc.

## Quyền cho task hiện tại

| Hành động | Phạm vi/nguồn |
| --- | --- |
| Read/edit | File hạ tầng, review, gitignore/pubignore, format checker và CI liên quan |
| Run checks | Formatter, analyzer và CI tests/build có sẵn; chỉ synthetic data |
| Network | Dependencies/GitHub CI và remote của repo theo công việc hiện có |
| Commit/push | Main của repo hiện tại, theo ủy quyền trong cùng hội thoại |
| Xóa/rewrite/deploy/secret access | Không cần và không thuộc task |

## Xong khi

- Có profile áp dụng, không thêm gate hỏi lại quyền đã cấp hoặc tự cấp quyền mới.
- Nhớ dài hạn có nguồn và nằm trong trần; nhớ ngắn hạn chỉ còn heading sau handover.
- Format checker kiểm đúng source folders, không sửa file và trả lỗi khi có sai format.
- CI stable gọi checker; root/adapter/example không bị lẫn kiểm chứng.
- Env files bị ignore đúng; .env.example còn có thể track, không chứa giá trị thật.
- Baseline/check results và giới hạn được ghi; gate sản phẩm không đổi.

## Kiểm chứng

| ID | Chạy/bằng chứng | Đạt khi |
| --- | --- | --- |
| STD-01 | Review diff và line counts | Raw rule byte-identical, memory có nguồn/trong trần |
| STD-02 | dart tool/check_format.dart | Pass source thật, không ghi lại file |
| STD-03 | Bản sao source synthetic có Dart sai format | Checker exit khác 0; file nguyên vẹn |
| STD-04 | git check-ignore --no-index trên tên giả | .env và biến thể bị chặn; .env.example không bị chặn |
| STD-05 | flutter analyze và Windows CI | Tool analyze, format gate và suite/build có sẵn đạt |
| STD-06 | Review handover/package exclusions | Chỉ metadata/tooling thay đổi; không claim physical pass |

Baseline formatter: 48 Dart files, 0 changes trên Flutter 3.47.7 trước thay đổi.
Baseline app suite: CI 40262146792 đúng runtime source, 108 package / 6 UVC /
7 example tests và Windows release build đạt 3.32.8/3.41.9/3.47.8.
Không thêm runtime code nên không cần camera thật để xác nhận task governance.
Web/auth/SQL scanners: n/a, không có bề mặt tương ứng và không thêm dependency.

## Commit và bàn giao

Có commit/push theo phạm vi đã cấp; mẫu [Chore] - Adopt project coding standards
and a stable format gate. Source/tools và evidence docs có thể tách commit.
Bàn giao .agent/handover/LATEST.md; trạng thái done chỉ cho task này sau các
check trên. docs/progress/HANDOVER.md vẫn là gate readiness sản phẩm.

## Giả định và giới hạn

Lựa chọn kỹ thuật trong task dùng repo và quyền review/bổ sung đã được giao,
không thêm yêu cầu sản phẩm mới. Raw rule có điểm máy móc/xung đột cần profile;
đó là kết quả review, không phải tuyên bố áp dụng vô điều kiện 1139 dòng.
