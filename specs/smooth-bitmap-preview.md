---
status: approved
slug: smooth-bitmap-preview
level: maintenance
updated: 2026-10-26
approved: 2026-10-26
approval_source: direct-user-request
source_idea: |
  Test thực tế thì có vẻ ổn, kiểm tra log xem có vấn đề gì k.
  Với phần preview camera nó đang có cảm giác chậm hơn so với thực tế và k mượt lắm.
---

# Preview bitmap cập nhật độc lập analysis

## Việc và nguồn

Review debug_log_5 dưới dạng dữ liệu. Log có 6/6 captures thành công (5 auto,
1 manual), camera gần 30 FPS nhưng analysis/bitmap hiện đi chung nhịp 5 FPS.
Tách delivery preview để giảm cảm giác trễ, giữ lượng công việc có giới hạn.
Nguồn: yêu cầu trực tiếp, source b66ce7f (runtime 7d789de), metadata log lần 5.

## Cách làm

- UVC dùng stream cache riêng cho analysis và bitmap; cùng tick cần cả hai thì
  chỉ copy/downsample native frame một lần. Analysis giữ interval và demand gate.
- Bitmap có interval riêng, example chọn target 15 FPS; giữ ≤640 px và không queue.
- Widget báo khả năng nhận frame qua handle riêng mỗi session: decoder bận hoặc
  preview unmount thì không copy chỉ để gửi ảnh sẽ bị bỏ.
- Controller có optional source contract để pause bitmap sampling trong capture,
  startup và teardown; adapter khác/custom source cũ không buộc đổi interface.
- Chi phí native copy/downsample được đo; preview-only sampling tự backoff khi
  frame đắt. Đây là heuristic giảm tải UI, không hứa tổng CPU hoặc 24/7.
- Health log phân biệt bitmap offered FPS/age, native FPS và analysis FPS, kèm
  mean/max sampling cost. Offered FPS không phải composited/display FPS.

## Không đụng

- External texture default/API đang dùng, SDK floor, dependency và native plugin.
- Crop/JPEG/quality thresholds, enum, resolution selector hoặc quy tắc lưu file.
- Không khẳng định optical blur/GPU/soak đã đạt từ log ngắn hoặc synthetic CI.

## Xong khi và test

| ID | Kiểm tra | Đạt khi |
| --- | --- | --- |
| PV-01 | Fake camera + bitmap widget, analysis interval 200 ms | Bitmap offers nhanh hơn analysis; sample có thể dùng chung; không đổi analysis gate |
| PV-02 | Widget decoder bị chặn/unmount/đổi session | Không readback thừa vì preview; late image dispose, old handle không khóa session mới |
| PV-03 | Controller capture/stop/dispose | Pause predicate đúng và được bỏ sau cleanup; camera vẫn single owner |
| PV-04 | Sample đắt + diagnostic metrics | Backoff có giới hạn, không queue; FPS/age/cost log rõ và không pixel/PII |
| PV-05 | Existing SDK suites + format/analyze/build | Regression cũ không hỏng; actual SDK/source ghi trong evidence |

## Quyền và bàn giao

Sửa các source/interface/test/docs liên quan preview theo yêu cầu mới; commit/push
main theo quyền cùng hội thoại. Không thay nội dung rule review để che diff.
Task rule giữ commit riêng và được hoàn tất check/handover cùng lượt CI cuối.
Bàn giao task này tại .agent/handover/LATEST.md sau khi archive handover rule.
