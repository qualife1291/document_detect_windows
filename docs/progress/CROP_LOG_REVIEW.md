# Review debug_log_2 và giữ mép crop — 2026-10-23

437 JSON events hợp lệ, khoảng 266.7 giây (06:19:25Z–06:23:51Z), cùng UVC
1280×720 và analysis 640×360. Chỉ ghi tổng hợp; raw log nằm ngoài Git.
Không có pixel ảnh gốc/crop để đo trực tiếp phần chữ bị mất.

## Quan sát từ log

- 11 capture attempts: 10 auto (9 thành công, 1 từ chối) và 1 manual thành công.
  Không có camera/worker error hoặc snapshot rejection.
- Auto 06:20:33Z bị từ chối đúng nhánh motion: maxCornerMotion 0.0155912,
  lớn hơn ngưỡng 0.015; qualityWarnings rỗng. Không nới ngưỡng chuyển động.
- Health analysis FPS trung vị 9.4, khoảng 6.2–10.0, so với khoảng 5 ở log đầu.
  Native delivered FPS trung vị 29.874; đây không phải composited/UI FPS.
  Analysis mean tích lũy 55–76 ms, cuối phiên 63 ms; max 159 ms; staleReports 0.
- Expiry tăng 10 lần, mỗi lần được ghi ở health interval chứa một capture thành
  công. Capture tạm dừng nhận analysis; counter này không đồng nghĩa lỗi camera.
- RSS mẫu đầu 235 MiB, cuối 299 MiB, min 215 / peak 335 MiB; 10 mẫu cuối tăng/giảm
  293–335 MiB. Phiên ngắn không chứng minh leak-free hay đáp ứng 24/7.
- Không có stop/dispose cuối phiên đang chạy; stop/stopped đầu log thuộc session
  0, nên chưa đủ bằng chứng cho thoát/unplug ở session 1.
- Processing thành công 412–555 ms; riêng encode JPEG gốc 277–396 ms,
  warp 29–63 ms. Encode ảnh gốc vẫn chiếm phần lớn thời gian. Chưa đạt gate
  end-to-end ≤300 ms; processing này cũng chưa bao gồm chờ stable feedback.

## Crop có đang cắt thêm do resize/filter?

`outputMaxSide=null`, `imageFilter=original`, filterMs=0 ở cả 10 ảnh thành công.
Quy đổi quad normalized về 1280×720 rồi tính độ dài hai cặp cạnh, cả 10 outputSize
đều khớp chính xác thuật toán warp hiện tại:

| Lần thành công | OutputSize |
| --- | --- |
| 1–4 | 588×301, 600×323, 620×361, 624×370 |
| 5–7 | 606×360, 604×357, 553×357 |
| 8–10 | 994×459, 982×444, 1000×478 |

Không thấy dấu hiệu sai scale tọa độ hoặc bước resize/filter cắt thêm hình.
Bản trước lấy đúng quad detect để warp, chưa chừa mép dự phòng. Quad được ước
lượng ở analysis 640 px; Gaussian/contour và giản lược hull có thể đặt góc vào
trong mép vật lý, đặc biệt với mép mờ/góc bo tròn. Đây là cơ chế có thể gây mất
chữ sát mép, chưa phải kết luận đo được từ pixel của người dùng. Việc chọn nhầm
vùng nội dung bên trong giấy cũng không thể loại trừ chỉ bằng log.

## Thay đổi tập trung vào crop

- Giữ detect preview, quality và motion checks hiện tại.
- `CropPipeline.cropPadding` mặc định `.02`: dịch mỗi đường cạnh ra ngoài bằng
  2% cạnh ngắn nhất, sau kiểm tra snapshot và trước homography. Áp vào các quad
  của log này tương đương khoảng 6–9 px mỗi cạnh; đây là tính toán dự kiến, chưa
  phải kết quả ảnh đã test lại trên camera.
- Giữ hướng bốn cạnh, tính giao điểm để bảo toàn phối cảnh; giới hạn offset chung
  theo biên sensor. Không lấy pixel ngoài ảnh. Nếu không đủ chỗ, padding bị giảm;
  giấy đã chạm biên có thể không nới thêm được. Có thể xuất hiện viền nền mỏng.
- Cho chỉnh `cropPadding` trong 0..0.1; `0` trả hành vi crop sát quad như trước.
  Không phục hồi được nội dung ngoài sensor hoặc quad nhận sai hoàn toàn.
- `CapturedDocument.quad` tiếp tục là góc detect. `cropQuad` là góc thực sự dùng
  warp, giữ cả khi lưu file; JPEG gốc không bị chỉnh sửa.
- `capture_processing` thêm normalized `cropQuad`, cropPadding,
  paddingRequestedPx, paddingAppliedPx, paddingLimited. `quad` vẫn là detect.
  `start` ghi cropPadding để phân biệt cấu hình mỗi phiên.
- Hình học offset chỉ xử lý bốn cạnh trên capture worker hiện có, không có lượt
  detect/copy ảnh mới trên preview. Crop có thêm một ít pixel cần warp/encode.

## Kiểm thử hồi quy

Mô phỏng detect lệch vào trong 1 px: crop sát quad mất các dấu nội dung ở cả bốn
mép, padding mặc định giữ được dấu ở cả bốn mép. Kiểm tra thêm phối cảnh,
portrait/rotation, sát/chạm biên sensor, padding=0, dữ liệu sai, scale 720p/5/8 MP,
byte JPEG gốc, cropQuad bất biến, strict motion check và metadata khi lưu file.
Các test kích thước crop trước đây được cập nhật theo margin mới; không nới
ngưỡng chất lượng hay bỏ regression về chuyển động/disposal.

## Test lại

Pull main, chạy example profile với `DOC_CAPTURE_LOGS=true` như README. Chụp giấy
có chữ sát cả bốn mép, auto/manual, góc bo/xiên và sát biên camera. So sánh JPEG
nguyên bản với ảnh crop; giữ `capture_processing` tương ứng. Cần cặp ảnh gốc/crop
để phân biệt sai quad, thiếu margin và nội dung đã ở ngoài sensor nếu còn mất chữ.
