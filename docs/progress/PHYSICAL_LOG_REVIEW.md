# Review log thực tế — 2026-10-23

Nguồn: `debug_log.txt` người dùng cung cấp, 375 JSON events trong khoảng 450 giây.
Chỉ lưu tổng hợp đã loại thông tin nhận diện. Không đưa raw log vào Git vì có
URI của debugger. Không có ảnh/video gốc để đo recall hoặc độ lệch viền thực tế.

## Kết quả quan sát được

- Windows, UVC, preset high, native frame 1280×720; analysis 640×360, interval
  100 ms, auto-capture bật. Camera được quảng cáo 5/8 MP chưa có nghĩa preset này
  đang cung cấp ảnh 5/8 MP.
- Native delivered FPS tiến gần 30; analysis gần 5 FPS dù frame gửi vào controller
  đều được nhận (`skippedAtController=0`). Analysis mean tích lũy khoảng 49–68 ms,
  max 301 ms; stale reports 0, expiry 3.
- Các **state events được in**, không phải số frame: noDocument 119, outOfFrame
  117, tilted 9, clear 8, blurry 1; các state khác là lifecycle/capture.
  Coalescing làm số lần xuất hiện khác số frame thực tế. Trong cùng các state
  events, warning phụ xuất hiện 109 lần tilt và 38 lần blur; enum chính ưu tiên
  framing nên chỉ đếm `tilted`/`blurry` sẽ bỏ sót các vấn đề đồng thời.
  Start ghi blurThreshold 100, brightness .2–.85, maxClipping .25; các clear events
  có blur 404–701. Log này chưa chứng minh cần nới ngưỡng rõ nét.
- Trong 117 outOfFrame events, 98 có margin dưới .02; 19 còn lại không đủ coverage.
  Có quad lớn chạm ba/bốn cạnh sensor, phù hợp giả thuyết chọn nhầm nền.
  Log không đủ để khẳng định nền đó là gì hay giấy nằm ở đâu.
- Auto chụp 04:04:52Z thành công, processing 628 ms, crop 52,981 bytes.
  Manual 04:06:31Z và 04:07:24Z bị từ chối; manual 04:07:45Z thành công,
  processing 670 ms, crop 39,270 bytes. Hai ảnh thành công cùng nguồn 1280×720.
- Hai manual rejection có thể suy ra từ nhánh code là không tìm được quad trên
  snapshot mới: manual bỏ qua quality và không truyền expected quad; không có
  snapshot/error rejection tương ứng. Bản log cũ chưa in lý do trực tiếp.
- Không thấy error event. Không có stop/dispose cuối phiên đang chạy nên chưa
  đánh giá được đóng cửa sổ/unplug bằng đoạn log này.
- RSS phiên hoạt động từ khoảng 228 MiB tới 319 MiB ở mẫu cuối, peak 335 MiB.
  Các mẫu cuối tăng/giảm theo GC; 7.5 phút không đủ kết luận có/không memory leak
  hoặc đáp ứng chạy liên tục 24/7.

## Sửa theo bằng chứng

1. Cadence: adapter hỏi demand trước copy/downsample nhưng controller cũ bắt đầu
   tính interval sau khi nhận bản copy. Poll kế tiếp sau 100 ms chưa đủ interval
   nên bị bỏ qua, tạo nhịp khoảng 200 ms. Gate mới đặt mốc ở lúc xin demand,
   cho phép jitter tối đa 5 ms riêng pull adapter; push adapter vẫn kiểm tra
   interval nghiêm ngặt. Backpressure/isolate queue vẫn giữ nguyên.
2. Contour: bỏ ứng viên ôm ba/bốn cạnh sensor, ưu tiên giấy đủ bốn góc bên trong
   so với vùng nền bị cắt. Nếu regular passes thất bại hoặc chỉ thấy vùng bị cắt,
   thử Canny nhạy hơn và đóng đứt viền nhỏ. Không giảm ngưỡng ảnh rõ/auto-stability.
   Đây vẫn là detector hình học, chưa phân loại được ID/medical bằng ngữ nghĩa.
3. Frame: mặc định trắng khi chưa rõ, xanh khi quality clear. API giữ tùy chọn
   màu và thêm `DocumentFrameStyle.outline`; example dùng viền khép kín.
   Không giữ viền cũ khi mất giấy; expiry vẫn hoạt động.
4. Crop: bilinear đọc/ghi buffer trực tiếp thay tạo Pixel theo mỗi điểm.
   Giới hạn output được áp dụng trước warp, tùy chọn; JPEG gốc vẫn full size.
   Filter original mặc định; enhance/grayscale opt-in và chỉ chạy sau capture.
5. Diagnostics: `capture_processing` ghi quyết định/lý do và stage times;
   health có auto-state/stableFrames/progress, start có thresholds. Không in ảnh,
   OCR text, đường dẫn hay native identifier.

## Tham khảo flutter_doc_scanner

Đã đọc source [flutter_doc_scanner 0.0.21](https://pub.dev/packages/flutter_doc_scanner/versions/0.0.21)
(archive SHA-256 `bd292288b64e1ec0ad9ac0b04454cef104fea9d63f7408cb70170591f92e11c6`).
Android giao UI/filter cho Google ML Kit Document Scanner, chế độ FULL trong
luồng thông thường. iOS dùng VisionKit; nhánh auto tùy chỉnh dùng Vision rectangle
request và CoreImage perspective correction. Không có Dart live detector dùng
chung để đưa thẳng sang Windows. Không thêm dependency mobile/native SDK vào
Windows package.

Áp dụng ý tưởng frame theo quadrilateral, sửa phối cảnh, xử lý sau capture và
output có giới hạn. Không sao chép mặc định ép portrait hoặc trả full image khi
không tìm được giấy: package này hỗ trợ giấy landscape và vẫn từ chối crop khi
snapshot không có quad. Contrast filter cục bộ là implementation riêng, không
khẳng định tương đương ML Kit/CoreImage.

## Bằng chứng kiểm tra

Hai synthetic scene mô phỏng nền sáng sát biên và giấy tương phản yếu cạnh vùng
sáng đều chọn nhầm vùng lớn trên baseline `469e6a1`; bản sửa chọn quad giấy đúng
với dung sai đã định trước. Noise âm tính vẫn không tìm giấy. Xem
[baseline regression](logs/physical-followup/baseline-detection-regression.txt).

Benchmark trước/sau dùng cùng Flutter 3.47.7 trên Linux cloud, tuần tự,
`flutter test` (không phải profile/release Windows):

| Synthetic 1280×720 | Baseline | Bản sửa |
| --- | --- | --- |
| Warp mean, 20 lần sau 3 warmup | 94.04 ms | 28.39 ms |
| Full capture mean, 3 lần sau warmup | 290.05 ms | 223.19 ms |
| Regular detection 640×480, 30 lần | 56.45 ms | 54.77 ms |

[Baseline](logs/physical-followup/linux-baseline-benchmark.txt),
[bản sửa](logs/physical-followup/linux-refined-benchmark.txt).
Số đo đơn lẻ có nhiễu và không xác nhận mức giảm latency trên camera người dùng.
Sensitive fallback có thêm chi phí khi regular passes thất bại; analysis vẫn bị
chặn theo demand/backpressure và giới hạn kích thước.

## Test lại trên thiết bị

Chạy example profile với `DOC_CAPTURE_LOGS=true` như README; thử từng lần manual
và auto, giấy sáng/tối trên nền khác nhau, ID landscape/portrait và medical form.
Giữ giấy rồi lấy ra để kiểm tra cooldown, thử mép sensor, phản quang, thiếu sáng,
đổi preset, rút camera và đóng cửa sổ khi đang chụp. Cần log từ startup đến stop;
đối chiếu `capture_processing.decision`, stage times, health FPS/stableFrames.
Đo native alignment/CPU/RSS và chạy soak 24–168 giờ vẫn là gate thiết bị thật.

## Validation lượt ca13fd4 (trước crop-margin follow-up)

Nguồn `ca13fd45e6bc96d37b2f551a86ccd68431de7232`; [Windows CI](https://github.com/qualife1291/document_detect_windows/actions/runs/39909113059)
đạt Flutter 3.32.8, 3.41.9, 3.47.7: 89 package tests, 3 example tests, hai
benchmark, endurance 60 s/SDK và build release Windows x64. Linux cũng đạt
analyze/suite tương ứng với endurance 30 s/SDK; adapter desktop analyze đạt
trên hai SDK hỗ trợ. Không skip/disable test.

Windows hosted VM, synthetic 1280×720, flutter-test; không phải latency camera:

| Flutter | Warp mean | Snapshot processing mean |
| --- | --- | --- |
| 3.32.8 | 46.27 ms | 282.46 ms |
| 3.41.9 | 27.04 ms | 183.88 ms |
| 3.47.7 | 47.60 ms | 290.11 ms |

Artifact gốc của các số đo này nằm trong workflow ca13fd4 ở trên. Sau lượt này
người dùng đã gửi debug_log_2; xem [review crop](CROP_LOG_REVIEW.md). Các file
`logs/windows-*` và provenance hiện tại được cập nhật theo lượt crop-margin mới.
Chưa xác nhận 24/7.

Evidence update: `logs/windows-*`, `logs/linux-*` và provenance hiện được cập
nhật theo lượt [GPU/performance follow-up](GPU_LOG_REVIEW.md); các số đo/source
lịch sử trong bài này thuộc workflow được liên kết tại thời điểm review.

Evidence update 2026-10-26: `logs/windows-*`, `logs/linux-*` và provenance hiện
được cập nhật theo [fourth-log follow-up](FOURTH_LOG_REVIEW.md). Các số đo/source
lịch sử trong bài vẫn thuộc workflow đã liên kết.

Evidence update: current SDK log folders và provenance được cập nhật theo
[fifth-log follow-up](fifth-log-review.md); số đo/source lịch sử ở đây thuộc
workflow đã liên kết trong chính lượt review đó.
