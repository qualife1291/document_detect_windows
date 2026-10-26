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
