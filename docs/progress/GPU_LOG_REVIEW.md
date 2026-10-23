# Review log thứ ba: treo giao diện sau nhiều lần chụp

Đã đọc `debug_log_3 (1).txt`, chỉ lưu số liệu tổng hợp đã bỏ thông tin định danh.
Không đưa raw log/debugger URL, tên thiết bị hoặc dữ liệu ảnh vào repository.

## Kết luận từ log

Log có **GPU device loss**, không chỉ hiện tượng detector chậm:

- Hai dòng `SwapChain11.cpp ... Present failed ... HRESULT: 0x887A0006`
  (`DXGI_ERROR_DEVICE_HUNG`), tiếp theo 398 lỗi EGL `Context Lost` và 397 lỗi
  `Could not make the context current to acquire the frame`.
- Lỗi đầu tiên xuất hiện giữa snapshot `09:27:55.508764Z` và health
  `09:27:55.651354Z` ngày 2026-10-23 (khoảng 16:27:55 giờ Việt Nam), trong
  lần chụp thứ sáu. Trước đó có ba lần thành công; sau lỗi vẫn có thêm hai lần
  xử lý ảnh thành công và health của Dart. Renderer hỏng trong khi analyzer sống
  phù hợp với cảm giác toàn bộ giao diện không thao tác được.
- Chưa xác định GPU driver, VRAM, nguồn tải khác hoặc việc external texture
  có trực tiếp kích hoạt lỗi hay không. Không suy ra chắc chắn lỗi driver hay
  leak từ riêng HRESULT này.

202 library events trong khoảng 161 giây: bảy lần chụp, năm thành công, hai
snapshot tự chụp bị loại vì `motion`. Đây là kiểm tra chuyển động, không phải
exception. Năm lần thành công xử lý 414–563 ms. Không có library `error`.
Không có stop/dispose cuối session đang chạy; stop đầu log thuộc session 0,
không dùng nó làm bằng chứng đã cleanup khi thoát.

32 mẫu health khi chạy: analysis 7.41–10.01 FPS, trung vị 9.8; native delivered
FPS trung vị 29.788 (không phải composited UI FPS). Mean analysis tích lũy
56–74 ms, max 148 ms; stale reports 0. RSS từ 220 MiB ở mẫu đầu, thấp nhất
207, cao nhất 273, cuối 253 MiB. Chưa có bằng chứng cạn RAM; RSS không đo VRAM
và khoảng đo này không đủ loại trừ leak. Năm expiry đi cùng các khoảng ngừng
analysis khi chụp, không tự nó chứng minh deadlock.

## Thay đổi sau review

- Example dừng/await camera trước khi hiện kết quả, gỡ live preview khi chuyển
  trạng thái và khởi động lại khi Chụp lại/Esc. Không duy trì camera/analyzer
  ở phía sau màn hình kết quả.
- Result decode chỉ phục vụ hiển thị, tối đa 1280 px. Evict đúng provider của
  kết quả khi thay/đóng; không clear cache toàn ứng dụng, không xóa file đã lưu.
  JPEG đầu ra/crop margin/radius không đổi.
- Thêm UVC bitmap preview tùy chọn: không tạo/attach external texture; dùng
  frame downsample ≤640 px, một decode đang chạy, bỏ frame khi bận, không queue
  lịch sử. Dispose image cũ ngay khi thay, kể cả không có frame được vẽ tiếp;
  dispose codec/buffer/descriptor và ảnh về trễ sau unmount.
- Example mặc định medium preset, sampling 200 ms và bitmap mode; ưu tiên mode
  native 15 FPS nếu thiết bị hỗ trợ. API adapter vẫn default texture/100 ms/30
  FPS preference để giữ tương thích. Tham số FPS là ưu tiên, không phải hard cap.
- Analyzer dispose bỏ các tham chiếu isolate/port/subscription/watchdog.
- `ui_health` mỗi 5 giây khi bật logs: UI timing/cache/result/camera state.
  Hướng dẫn copy giữ cả engine errors; lọc chỉ library sẽ làm mất lỗi GPU này.

Bitmap mode giảm tải và tránh đường camera external texture, **không đảm bảo
bypass GPU**: Flutter Windows vẫn có thể dùng GPU để render bitmap/UI. Không
hứa tự khôi phục rendering context sau device loss. Không coi
`--enable-software-rendering` là cách sửa đã được xác nhận trên Windows SDK
floor: engine vẫn khởi tạo EGL và release không đọc các engine-switch environment
variables như debug/profile. Nếu lỗi lặp lại, restart app và đo lại trên máy thật
với thông tin GPU/driver, so sánh bitmap/texture trong cùng điều kiện.

## Kiểm chứng và giới hạn

Regression tests bao gồm decoder backpressure, dispose sau unmount/đổi stream,
30 lần decode không painting, không dùng image cache, source-error không tạo
feedback loop; UVC bitmap/texture start/stop/failure/retry, FPS preference và
full-resolution snapshot; chờ native stop trước result, sáu chu kỳ chụp/chụp lại,
cache chỉ evict ảnh của result và display decode có giới hạn.

CI/synthetic tests không tái hiện D3D GPU hang của máy người dùng và không chứng
minh khả năng chạy 24/7. Cần retest camera thật với cấu hình mặc định mới, chụp
nhiều vòng, unplug/đóng cửa sổ khi đang capture và soak dài theo
[continuous operation](../continuous_operation.md). Log UI-frame age khi app đứng
im có thể lớn bình thường; cần đối chiếu lỗi engine và thao tác người dùng.
