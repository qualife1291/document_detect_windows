# Trạng thái triển khai

Cập nhật: 2026-10-23 (Asia/Saigon). Đây là tiến độ nội bộ; chưa handover.

| Phase | Platform bắt buộc | Trạng thái | Bằng chứng / phần còn thiếu |
| --- | --- | --- | --- |
| 1 — Skeleton & camera preview | Windows x64 | Đang làm | Có native architecture guard, FrameSource và hai adapter; đã build Windows trên ba SDK, còn preview camera thật/latency |
| 2 — Detection & quality | Windows x64 | Đang làm | Có grayscale/Gaussian/Canny/contour/quad, quality isolate và synthetic tests; đã benchmark synthetic Windows CI, còn benchmark kiosk target |
| 3 — Warning & auto-capture | Windows x64 | Đang làm | Có callback enum preview, overlay 4 góc contain/cover, expiry, kiểm tra chuyển động, feedback ≥500 ms và cooldown; cần camera thật |
| 4 — Crop & output | Windows x64 | Đang làm | Có homography, snapshot mới, kiểm tra chuyển động lại, JPEG/file tests; cần 4K/DPI/camera Windows |
| 5 — Hardening & handover | Windows x64 | Đang làm | Có Windows SDK build/test logs và tài liệu; còn camera thật/accessibility/backend comparison |

## Hai candidate camera

| Candidate | Metadata đã kiểm tra qua pub.dev | Đo latency / độ ổn định Windows | Quyết định |
| --- | --- | --- | --- |
| camera_desktop 2.0.0 | Yêu cầu Dart ^3.11.0; không resolve trên sàn 3.8.1 | Chưa làm | Adapter tùy chọn, tách dependency graph; chưa chọn default |
| flutter_ffi_uvc 1.1.2 | Dart ^3.8.1; Media Foundation + native Texture, API copy frame | Chưa làm | Example chọn rõ candidate thử nghiệm; chưa chọn default |

Không có số đo camera-to-texture, CPU/driver hoặc chứng cứ Windows để chọn
backend production. Dependency candidate chỉ nằm trong package adapter riêng.
`dartcv4` chưa tích hợp; facade dùng pure Dart trên mọi SDK hiện tại.

## Phạm vi kiểm chứng

Máy cloud là Linux x86_64. Bằng chứng supplemental nằm trong
`docs/progress/logs/linux-*/`. Native build/test có bằng chứng riêng từ Windows
GitHub Actions; không suy ra camera runtime từ synthetic tests.
Tên `windows_doc_capture` trả HTTP 404 khi kiểm tra pub.dev API ngày 2026-10-22;
chưa đăng ký/publish tên. Kho GitHub ban đầu chưa có commit/ref và được triển
khai từ đầu theo đặc tả người dùng cung cấp.

## Cập nhật preview — 2026-10-23

Đã triển khai DocumentPreviewState / onDocumentStateChanged, previewStatus và
overlay bốn góc trong API dùng chung. Detection vẫn chạy khi tắt auto-capture.
Có kiểm thử ảnh synthetic cho quality enums, geometry khi letterbox/crop/4K,
callback dedup, capture lifecycle, restart/error và xóa marker quá hạn.
Pub get/analyze, 38 package tests, 2 example tests, benchmark và release build
Windows đã đạt trên Flutter 3.32.8, 3.41.9, 3.47.7 tại commit `5588f6d`.
Linux cũng đạt ba SDK. Camera thật và accessibility gates vẫn chưa hoàn thành.

## Hardening — 2026-10-23

Đã sửa backpressure, hủy crop worker, quyền sở hữu camera, serialize adapter,
startup/dispose và stale cooldown; thêm document/light/5–8 MP/lifecycle tests.
Linux đã đạt cả ba SDK: 66 package tests, 3 example tests, benchmark và
endurance 30 s. Adapter desktop analyze đạt 3.41.9/3.47.7. Lượt tải phát triển
300 s có log riêng; chưa xác nhận 24/7 trên thiết bị thật.
Windows CI cũng đã đạt cả ba SDK tại `de48bba`: analyze, 66/3 tests,
benchmark, endurance 60 s/SDK và release build. Camera thật/24–168 h vẫn chưa chạy.

## Diagnostics — 2026-10-23

Đã thêm debugPrint JSON với lifecycle/state/capture/error và health mỗi 5 giây,
coalesce trạng thái nhanh, redact dữ liệu/đường dẫn và hủy timer lúc đóng.
Linux đã đạt ba SDK: analyze, 76 package tests, 3 example tests, benchmark
và endurance. Có 10 test riêng cho diagnostics/redaction/timer/sink failure
và phiên ngắn.
Windows CI cũng đã đạt ba SDK tại `bbf00d4`: analyze, 76/3 tests,
benchmark, endurance 60 s và build release.

## Theo log thực tế — 2026-10-23

Đã review 450 s log, sửa cadence pull adapter, ưu tiên quad đầy đủ, fallback
viền yếu, frame trắng/custom/outline, warp byte-buffer, filter opt-in và lý do
capture rejection. Linux/Windows đạt cả ba SDK: 89 package tests, 3 example
tests, hai benchmark, endurance 30 s Linux / 60 s Windows và Windows release build.
Windows source `ca13fd4`, [workflow](https://github.com/qualife1291/document_detect_windows/actions/runs/39909113059).
Số đo synthetic không thay camera thật/24–168 h; xem [review](PHYSICAL_LOG_REVIEW.md).

## Crop theo log thứ hai — 2026-10-23

Log 437 events: 10/11 capture thành công, 1 motion rejection, không có error;
analysis FPS trung vị 9.4. Đã thêm cropPadding mặc định .02, bounded source-frame
geometry và cropQuad riêng, giữ detect/quality/motion và JPEG gốc. Linux/Windows
đạt ba SDK: 102 package tests, 3 example tests, hai benchmark, endurance 30/60 s
và Windows x64 release build. Source `b83c42c`, [workflow](https://github.com/qualife1291/document_detect_windows/actions/runs/39915232027).
Preview thêm cornerRadius mặc định 0, example chọn 6 px.
Chưa đo mất chữ trên pixel người dùng; xem [review crop](CROP_LOG_REVIEW.md).

## Treo GPU theo log thứ ba — 2026-10-23

Log có 0x887A0006 / EGL Context Lost trong khi Dart analyzer tiếp tục chạy,
5/7 lần chụp thành công, hai motion rejection; chưa chứng minh leak/cạn RAM.
Đã thêm UVC bitmap preview, dispose ảnh thay thế/ảnh đến trễ, cấu hình example
medium/200 ms/≤640 px, dừng camera trước result, giới hạn display decode và
evict provider đúng chủ sở hữu. Crop pipeline giữ nguyên; medium có thể chọn
stream nhỏ hơn high, display cap không resize JPEG.
Windows/Linux đạt ba SDK: 108 package, 4 UVC adapter, 6 example tests, hai
benchmark, endurance 30/60 s và Windows x64 release build. Source `65948cf`,
[workflow](https://github.com/qualife1291/document_detect_windows/actions/runs/39944214256). Chưa retest GPU/driver trên máy người dùng, chưa
xác nhận 24–168 h. Xem [review](GPU_LOG_REVIEW.md).

## Preview nhấp nháy / log thứ tư — 2026-10-26

Log 148 events, ba lần auto thành công, crop ~780×350 px, không có library error
hay D3D/EGL trong file gửi. Đã tái hiện stream-wrapper identity thay đổi làm
bitmap reset ảnh khi status rebuild. Cache stream và kiểm tra 30 rebuild với
decoder thật. Result dùng scaleDown theo DPI, preset high độc lập low-resource
và có lựa chọn mode cho lần chụp. Không đổi crop/JPEG/thresholds.
Windows/Linux đạt ba SDK: 108 package, 6 UVC adapter, 7 example tests, hai
benchmark, endurance 30/60 s và Windows x64 release build. Source `7d789de`,
[workflow](https://github.com/qualife1291/document_detect_windows/actions/runs/40262146792). Chưa chứng nhận JPEG quang học, hardware GPU
hoặc 24–168 h sau bản sửa. Xem [review](FOURTH_LOG_REVIEW.md).

## Log 5 / preview cadence và coding standard — 2026-10-26

Đã đọc 433 events/~420 s, 6/6 capture accepted, không library/GPU error trong
file; native ~30 vs analysis/bitmap 5 FPS. Tách bitmap target ~15 khỏi analysis
200 ms, một readback khi chung demand, upstream readiness, pause capture và
chi phí copy/downsample backoff. Health mới tách FPS/age/cost; không hứa physical
composited FPS. Governance được review theo profile, giữ nguyên raw standard,
thêm AGENTS/memory/handover/env ignore và stable format gate.
Source `a9e29c4`, [CI](https://github.com/qualife1291/document_detect_windows/actions/runs/40267546967), Windows 3.32.8, 3.41.9, 3.47.8
và Linux 3.32.8/3.41.9/3.47.7 đạt 110 package, 9 UVC, 7 example tests, hai
benchmark/endurance 30/60 s; Windows release build và formatter 49 files đạt.
Physical preview/GPU/optical quality/accessibility/24–168 h chưa được chứng nhận.

## Adaptive preview/detail — 2026-10-26

Done source `b6076ff9d8a07c07535fd3ee3d0e53c40b23b398`:
[CI 40283388912](https://github.com/qualife1291/document_detect_windows/actions/runs/40283388912).
Native resize trước FFI; profile 640/960/1280 và load sampling/decode/host UI;
cadence từ sampling start; visibility/late-session cleanup; exact pixel crop;
exampleJPEG 92, actual MP/aspect-aware document size hints. BSD backend namespace
riêng, provenance/license đầy đủ. Host chứa cả hai plugin build thành công.
Windows 3.32.8/3.41.9/3.47.8 đạt 116/11/7 tests, 3 benchmarks, native CTest,
endurance 60 s, release build; formatter 56 files. Linux supplemental/root/example
cùng source tree, final adapter kiểm lại ba SDK; endurance 30 s.
[Review](adaptive-preview-detail.md), [coverage](logs/adaptive-preview-detail/source.json).
Product gate vẫn CHUA DAT; không suy ra physical clarity/GPU/soak từ CI.

## Export original/crop pair trong example — 2026-10-26

Done source `2a1644b06ca429c31a882a76dee1d59bde6fa279`:
[Windows CI 40298617835](https://github.com/qualife1291/document_detect_windows/actions/runs/40298617835).
Windows 3.32.8/3.41.9/3.47.8 đạt 116/11/18 tests, 3 benchmarks/native CTest,
endurance 60 s, release build, stable format 58 files và coexistence build.
Linux 3.32.8/3.41.9/3.47.7 đạt example analyze/18 tests. Export native picker
chỉ trong example; root/camera/adapter/CI source trees trùng baseline f4e215c.
Byte-copy pair + owned staging, cancel/error/retry/exit/unmount được kiểm chứng;
physical pair visual review và thao tác folder dialog thật còn thiếu.
[Review](export-capture-pair.md), [coverage](logs/export-capture-pair/source.json).
Gate sản phẩm vẫn CHUA DAT.
