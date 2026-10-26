# Preview thích nghi và giữ chi tiết ảnh chụp

Nguồn: người dùng chấp nhận đề xuất sửa cadence, tách preview/analysis, giữ ảnh
native, cải thiện crop/JPEG và hướng dẫn chất lượng; nhấn mạnh app tích hợp có UI
nặng và thiết bị yếu. Quyền commit/push/merge đã cấp trong hội thoại.

## Phạm vi đã được yêu cầu

- Cadence tính từ lúc bắt đầu sampling, không cộng chi phí vào chu kỳ.
- Preview có profile 640/960/1280, không upscale; analysis độc lập <=640.
- Giảm tải theo sampling/decode/UI frame cost, phục hồi chậm, không queue ảnh.
- Native thu nhỏ trước khi copy qua FFI. Backend Windows nội bộ dựa trên BSD
  flutter_ffi_uvc 1.1.2, tên plugin/DLL/channel riêng để tránh ghi đè host plugin.
  Giữ attribution/provenance; không fork mobile/libuvc hay sửa pub-cache.
- Snapshot vẫn full negotiated mode. Crop thẳng chỉ dùng khi hình học chính xác;
  JPEG benchmark trước khi chọn example default. Không sharpen/upscale giả.
- Hiển thị actual resolution và hướng dẫn kích thước giấy/focus phù hợp tỉ lệ.
- Giữ lease/operation serialization, cleanup, cancellation, privacy diagnostics;
  offscreen/inactive consumer không kéo preview; app không mất quyền sở hữu cache.

Không đổi detector thresholds để làm số liệu đẹp, không OCR, không tự đổi focus
camera, không đổi storage policy, không hứa 24/7 hay ảnh sắc hơn giới hạn quang học.

## Kiểm chứng / hoàn thành

Regression cadence với copy chậm; busy/hidden/dispose/late decode; adaptation
hysteresis; native scaled bounds/5–8MP; full snapshot; crop pixel integrity.
Analyze/test riêng root/backend/adapter/example; SDK floor + Windows CI build.
Ghi source/SDK/kết quả, cấu hình tích hợp, giới hạn physical camera/driver rõ ràng.
Task code có thể done trong khi gate sản phẩm HANDOVER vẫn CHUA DAT.
