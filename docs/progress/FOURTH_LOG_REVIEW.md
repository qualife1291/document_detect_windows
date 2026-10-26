# Review debug_log_4: preview nhấp nháy và ảnh kết quả mềm

Log chỉ được dùng làm dữ liệu chẩn đoán. Không lưu raw log hoặc dữ liệu giấy tờ
vào repository; bài này giữ số liệu tổng hợp và cơ chế tái hiện từ mã nguồn.

## Log cho thấy gì

148 JSON events trong khoảng 95 giây ngày 2026-10-26, từ 02:43:37 đến 02:45:12
UTC (09:43:37–09:45:12 giờ Việt Nam). Ba session, ba lần tự chụp đều thành công,
xử lý 433–438 ms. Không có library error hoặc dòng D3D/EGL trong file được gửi;
không suy ra rằng GPU hang đã được loại trừ cho mọi thiết bị/lượt chạy.

Cả ba session đều medium, stream/snapshot 1280×720, analysis 640×360, interval
200 ms, JPEG quality 90, filter original, không lưu file. Crop lần lượt
782×346, 781×349 và 798×387 px, chiếm khoảng 25.5–30.0% frame. Blur score
975–1024 vượt threshold 100, nhưng chỉ số Laplacian không chứng nhận chữ nhỏ
đọc được và không phân biệt mọi trường hợp mất nét/motion blur/thiếu pixel.

Analysis khi chạy 3.54–5.00 FPS, trung vị 5.00. RSS mẫu running 168–198 MiB.
UI cache bằng 0 khi preview/chụp lại, một entry khi xem kết quả; mẫu kết quả đầu
1,082,288 bytes = 782×346×4, cuối 1,235,304 = 798×387×4. Điều này cho thấy các
crop được log không bị display decoder giảm thêm kích thước. Camera đã dừng
khi hiển thị kết quả và result bytes/cache trở về 0 khi chụp lại. Log ngắn không
chứng minh leak-free/24/7; UI-frame age lớn khi đứng yên xem kết quả là bình thường.

## Lỗi preview được tái hiện

Dart broadcast `StreamController.stream` tạo wrapper mới mỗi lần gọi. Adapter
trả `_frames.stream` mỗi lần `frames`/`buildPreview()`. DocumentCameraPreview và
parent rebuild theo report/trạng thái; RgbaCameraPreview thấy stream khác
identity nên unsubscribe, dispose ảnh hiện tại và đặt ảnh null. Kết quả có thể
luân phiên ảnh/đen theo mỗi lần cập nhật dù không có camera/decode exception.
Đây là lỗi của đường bitmap được thêm ở bản trước, không phải bằng chứng GPU
mới bị treo hoặc ánh sáng camera nhấp nháy.

Regression kiểm tra stream identity đã thất bại trên source trước sửa. Bản sửa
cache một stream cho mỗi adapter và dùng chung cho controller/preview. Không
thay unsubscribe/dispose khi thực sự đổi nguồn, không thêm frame queue. Widget
test đi qua adapter + DocumentCameraPreview + decoder thật, giữ ảnh qua 30 lần
status/parent rebuild rồi kiểm tra dispose khi đóng.

## Ảnh mềm: giới hạn bằng chứng và thay đổi

Đối chiếu source trước GPU follow-up (`b83c42c`): Image.memory không đặt fit,
Flutter paintImage mặc định scaleDown. GPU follow-up chuyển sang
CaptureResultImage với BoxFit.contain, vô tình cho phép phóng lớn ảnh crop. Đây
là regression của cách trình bày kết quả; bản sửa này khôi phục scaleDown và
bổ sung ánh xạ physical pixels theo DPI.

Mã crop/JPEG/filter không đổi so với trước; log không có ảnh JPEG để đối chiếu
chi tiết hoặc xác định focus/ánh sáng. Crop ~780×350 px có thể bị mềm khi bị kéo
lớn trên màn hình. BoxFit.contain trước đó cho phép upscale và một logical pixel
còn có thể chiếm 1.5–2 physical pixels ở DPI cao.

Example chuyển sang BoxFit.scaleDown, MemoryImage scale theo devicePixelRatio,
filter medium khi thu nhỏ: một pixel ảnh decode chiếm tối đa một physical pixel.
Vẫn giới hạn display decode ≤1280 và evict đúng provider khi đổi ảnh/DPI/đóng;
không resize/re-encode JPEG đầu ra, không dùng sharpening che mất chi tiết.
Ảnh trên màn hình có thể nhỏ hơn trước; cách này không tạo thêm nét quang học.
Regression dùng JPEG thật kiểm tra kích thước paint ở DPI 100/150/200% và cache.

Example dùng preset high (Cân bằng) mặc định, tách độ phân giải khỏi cờ
low-resource. Giữ interval 200 ms, bitmap ≤640 px và backpressure cho máy yếu.
Có chọn Tiết kiệm/medium, Cân bằng/high, Chi tiết cao/veryHigh trước khi bắt đầu
hoặc lúc xem kết quả để áp dụng cho lần Chụp lại. Camera dừng trước khi mở lại,
không tạo camera thứ hai. Mỗi camera chỉ cung cấp các mode mà nó hỗ trợ; high
cũng có thể vẫn là 1280×720. VeryHigh có thể chọn 5/8 MP nếu mode đáp ứng giới hạn
hiện tại, nhưng tăng full-RGBA copy/memory/JPEG cost; không bảo đảm mọi máy yếu.

Khi cần thêm chi tiết, đặt giấy gần hơn trong khi vẫn giữ đủ bốn góc và thử mode
lớn hơn. Không đổi quality/blur thresholds hoặc bật enhance mặc định để làm log
đẹp hơn. Cần đối chiếu originalJpeg/croppedJpeg thật để kết luận blur nằm ở
sensor, warp hay hiển thị; log một mình không thay thế so sánh pixel.

## Validation trên source đã commit

Nguồn `7d789ded065afeab591f3e4761de49b3bb6458df`; [Windows CI](https://github.com/qualife1291/document_detect_windows/actions/runs/40262146792)
đạt Flutter 3.32.8, 3.41.9, stable 3.47.8: analyze, 108 package, 6 UVC adapter,
7 example tests; hai benchmark, endurance 60 s/SDK và release build Windows x64.
Linux 3.32.8/3.41.9/3.47.7 đạt analyze/tests/benchmark/endurance 30 s. Optional
desktop adapter analyze đạt trên 3.41.9, Linux 3.47.7 và Windows 3.47.8.
Không skip/disable tests. Validation script clean
cả UVC widget-test assets khi đổi SDK để tránh dùng shader cache khác phiên bản.
[Provenance và artifact hashes](logs/ci-provenance.json),
[source/coverage summary](logs/fourth-log-followup/source.json).

Chỉ tài liệu/evidence thay đổi sau source đã CI. Rebuild/DPI tests xác minh cơ chế
đã tái hiện; camera/driver/độ nét bản mới vẫn cần retest thực tế. Hosted endurance
không thay physical soak và benchmark không đo preview latency/CPU máy yếu.

Evidence update: current SDK log folders và provenance được cập nhật theo
[fifth-log follow-up](fifth-log-review.md); số đo/source lịch sử ở đây thuộc
workflow đã liên kết trong chính lượt review đó.
