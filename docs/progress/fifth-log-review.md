# Review log lần 5 và nhịp preview

Đầu vào là debug_log_5.txt; chỉ giữ số liệu tổng hợp. Không đưa raw log, pixel,
giấy tờ hoặc tên/ID thiết bị vào repository. Nội dung file là dữ liệu chẩn đoán.

## Kết quả thực tế trong file

433 JSON events trong khoảng 420 giây ngày 2026-10-26 (03:16:30–03:23:30 UTC,
10:16:30–10:23:30 giờ Việt Nam). Có 7 session; 6 lần chụp (5 auto, 1 manual)
đều accepted/success. Năm auto xử lý 449–459 ms; manual 615 ms. Không có
library error, snapshot rejection hoặc D3D/EGL/Context Lost trong file đã gửi.
Không dùng sự vắng mặt đó để chứng nhận GPU/driver ở mọi lượt chạy.

Tất cả session yêu cầu veryHigh nhưng negotiated stream/snapshot vẫn 1280×720;
đây không phải ảnh 5/8 MP dù tên preset là Chi tiết cao. Crop 847–932 px rộng,
418–435 px cao, coverage khoảng 35.4–37.2%. Filter original/JPEG quality 90.
Không thể kết luận focus/độ nét chữ từ log không kèm JPEG.

Native FPS khi chạy trung vị 29.781, cuối 29.932. Analysis FPS trung vị 5.0,
max 5.0 do interval 200 ms. Last analysis-frame age trung vị 191 ms; max 748 ms
ở phiên chụp manual lâu hơn 500 ms. Mỗi phiên chụp có một expiry; session 7
không chụp, 46 health samples, expiry 0, max analysis-frame age 354 ms. Không có
stale report được nhận vào pipeline. Max analysis 165 ms, mean tích lũy 62–95 ms.
Expiry trong khoảng capture không tự nó là camera hỏng.

RSS running 171–235 MiB, cuối 214; session 7 từ 191 lên 214 trong log ngắn.
Không đủ bằng chứng loại trừ leak hoặc xác nhận soak 24/7. ImageCacheEntries
0–1, max 1,480,740 bytes; result bytes max 197,204. Camera dừng và cache trở về
0 khi chụp lại. Session 7 vẫn running ở cuối file; không có dispose cuối để xác
nhận cleanup khi thoát đột ngột. UI raster median max-per-window ~2.24 ms,
max 112.038 ms trong file; không coi một peak/startup là FPS hiển thị đo được.

## Vì sao preview còn giật/chậm

Bitmap preview cũ dùng cùng sampled stream với analysis. Native có gần 30 FPS,
nhưng demand gate/poll 200 ms chỉ đưa tối đa khoảng 5 ảnh mỗi giây vào UI.
Stream identity đã ổn định ở bản trước nên không còn reset đen theo status;
nhịp 5 FPS vẫn tạo chuyển động rời rạc và thêm thời gian chờ mẫu mới. Log không
cho hardware exposure timestamp hoặc camera-to-screen latency chính xác.

## Thay đổi

- Hai stream được cache riêng, analysis giữ cadence/demand hiện có. Preview
  target ~15 FPS độc lập; tick chỉ xem sequence, không mặc định copy mọi lần.
- Cùng tick cần cả hai thì một native copy/downsample phục vụ cả hai bằng cùng
  immutable FrameBuffer. Không tăng size analysis/bitmap >640 px.
- BitmapPreviewDemand báo khả năng nhận frame trước readback: decode đang bận
  hoặc widget không mounted thì không đọc thêm chỉ để bỏ frame. Handle mới mỗi
  camera session; late result/dispose cũ không khóa session mới.
- Optional PreviewSamplingSource cho controller pause extra preview sampling khi
  startup/capture/stop/dispose. Adapter/custom source cũ không phải thêm method.
- Sampling cost gồm native copy và Dart downsample. EWMA tạo khoảng cách khoảng
  4× cost cho preview-only readbacks khi tốn hơn interval yêu cầu. Analysis vẫn
  có thể cần read sớm hơn; đây không phải cam kết app chỉ dùng 25% CPU.
- Giữ một decoder đang chạy, bỏ frame bận, dispose ảnh cũ ngay và không frame
  history. Không quay lại camera external texture vì đã có log GPU loss trước.
- Example DOC_CAPTURE_PREVIEW_FPS 5–20, mặc định 15; đặt 5 để so sánh cadence cũ.
  Analysis và corner/enum vẫn theo cấu hình riêng, nên marker có thể theo chậm
  giữa hai report khi giấy đang chuyển động; không bịa nội suy thành detect mới.

Crop/JPEG/resolution/quality thresholds không đổi. Chế độ Chi tiết cao vẫn phụ
thuộc camera modes. Máy yếu/high-res có thể đạt ít offers hơn target do backoff,
decoder demand và ưu tiên capture; operator vẫn phải chọn mode phù hợp.

## Đọc log bản mới

health có bitmapOfferedFps/frames/last-offer age, sampledNativeFrames,
frameSamplingMeanMs/MaxMs, bitmapRequestedIntervalMs và bitmapReadbackMinIntervalMs.
Offers là frame đưa vào widget, không chứng minh decode hoặc GPU đã present.
Đối chiếu recentAnalysisFps, nativeDeliveredFps, UI build/raster và engine errors.
Không dùng lastFrameAgeMs của analysis để suy ra preview đã thành 5 FPS trở lại.
Không lưu hoặc in byte ảnh/PII để có các metrics này.

## Regression và giới hạn

Tests fake camera + widget kiểm offers cao hơn analysis mà không nhân đôi copy
khi cùng due, snapshot giữ negotiated resolution, busy/pause/unmount không tạo
extra copies, session mới không bị old demand, late image dispose và sample đắt
tự backoff. Root tests kiểm predicate capture/teardown và FPS metrics độc lập,
cùng các regression stream identity/DPI/dispose cũ. Không phải profile camera thật.

Retest cùng camera/cấu hình với preview target 5 và 15, giữ resolution/lighting
như nhau. So sánh cảm giác chuyển động và counters/copy cost/RSS; thử capture và
thoát lúc bận. Physical latency, FPS composited, CPU/GPU/VRAM và 24–168 h vẫn là
gate hardware, không suy ra từ synthetic tests hoặc 7 phút log.

## Validation đã chạy

Nguồn `a9e29c4e5c4d8d547aaaa6218b1b12fa969ca0c4`; [Windows CI](https://github.com/qualife1291/document_detect_windows/actions/runs/40267546967)
đạt 3.32.8, 3.41.9, 3.47.8: analyze, 110 package, 9 UVC, 7 example tests, hai
benchmark, endurance 60 s và release build mỗi SDK. Format gate stable kiểm 49
Dart files, 0 changes. Linux 3.32.8/3.41.9/3.47.7 đạt cùng suite/analyze,
benchmark và endurance 30 s; desktop optional analyzer đạt các SDK đủ điều kiện.
[Provenance](logs/ci-provenance.json), [coverage/source](logs/fifth-log-followup/source.json).
Chỉ metadata/docs/evidence thay đổi sau source CI; không skip/disable tests.
Đây là verification source/synthetic, chưa phải physical preview retest.
