Handover: CHUA DAT

# Bằng chứng bàn giao — 2026-10-22

Chưa đạt mục 9.1, 9.2 và 9.3 của đặc tả. Máy hiện tại là Linux x86_64,
không có Windows runner hoặc camera thật. Không có kết quả Windows nào được
suy ra từ Linux. Không tuyên bố hoàn tất bàn giao hoặc sẵn sàng production.

| Gate | Trạng thái | Còn thiếu |
| --- | --- | --- |
| 9.1 Build & Test Windows x64 | Chưa đạt | Analyze/test/build example và integration camera thật, benchmark Windows có log |
| 9.2 Ba SDK trên Windows | Chưa đạt | Cả ba SDK cần pub get/analyze/test/build Windows và version thật trên Windows |
| 9.3 Accessibility / Nielsen | Chưa đạt | Inspection Windows, 0 critical/serious, contrast/keyboard/reduced-motion trên bản build và review đủ 10 heuristics |
| 9.4 Tài liệu | Đạt — review source | README/CHANGELOG/SECURITY/platforms/limitations khớp phạm vi hiện có; giới hạn và các phép đo chưa làm được ghi rõ |

## Kết quả supplemental trên Linux

Các lệnh thật đã chạy trong package, adapter UVC và example bằng
`tool/validate_linux.sh`. Mỗi SDK có 24 core tests, 2 widget tests và 1 benchmark
test (30 ảnh synthetic, thêm 5 warmup). Không skip/disable/expected-failure trong
các suite này. Integration Windows chưa chạy, không tính vào số test đã đạt.

| Flutter | pub get package/example | analyze package/example | Core / widget / benchmark | Synthetic mean / FPS | Log |
| --- | --- | --- | --- | --- | --- |
| 3.32.8 | Đạt / Đạt | Đạt / Đạt | 24 / 2 / 1 đạt | 78.93 ms / 12.67 FPS | [logs](logs/linux-3.32.8/) |
| 3.41.9 | Đạt / Đạt | Đạt / Đạt | 24 / 2 / 1 đạt | 73.62 ms / 13.58 FPS | [logs](logs/linux-3.41.9/) |
| 3.47.7 | Đạt / Đạt | Đạt / Đạt | 24 / 2 / 1 đạt | 78.75 ms / 12.70 FPS | [logs](logs/linux-3.47.7/) |

UVC adapter cũng pub get/analyze đạt trên cả ba SDK. Adapter camera_desktop
pub get/analyze đạt trên Flutter 3.41.9, log
[desktop-adapter-analyze-3.41.9.txt](logs/desktop-adapter-analyze-3.41.9.txt).
Không resolve adapter này trên sàn 3.32.8 vì upstream yêu cầu Dart 3.11; nó
không nằm trong dependency graph của root package và example.

Benchmark trên đây dùng `flutter test` trên Linux, không phải kiosk release.
Không đo native camera-to-texture, CPU, physical preview FPS hoặc end-to-end
≤300 ms. Counter native delivered FPS trong example chưa được kiểm chứng bằng
camera thật. `CapturedDocument.processingTime` không bao gồm chờ feedback stable.

### Lỗi setup đã chẩn đoán và khắc phục

Khi chuyển từ SDK 3.32.8 sang 3.41.9, test assets cũ gây lỗi runtime shader
format (`Expected 1, got 0`). Lưu lần lỗi ở
[diagnosed-sdk-cache-3.41.9.txt](logs/diagnosed-sdk-cache-3.41.9.txt).
Chạy `flutter clean` cho package/example trước từng SDK sửa được lỗi; script
validation đã cập nhật. Các log matrix phía trên thuộc lượt chạy lại đã đạt,
không phải bỏ qua lỗi. Cache Dart/Flutter được chuyển sang `/workspace` qua
cấu hình được hỗ trợ vì home của máy là read-only. TLS/checksum vẫn bật.
Bootstrap dependency script đã chạy thành công và chạy lại thành công;
[bootstrap-repeat.txt](logs/bootstrap-repeat.txt) ghi lượt kiểm tra lặp lại.

## Windows x64 — toàn bộ bằng chứng còn thiếu

| Hạng mục | Trạng thái | Runner / log còn cần |
| --- | --- | --- |
| Analyze package + example | Chưa chạy Windows | Windows x64, mỗi SDK, log từ tool/verify_windows.ps1 |
| Unit / widget test | Chưa chạy Windows | Windows x64, mỗi SDK, counts và exit status thật |
| Build example release | Chưa chạy | flutter build windows trên cả ba SDK |
| Real camera integration | Chưa chạy | example/integration_test/real_camera_test.dart; operator đặt/bỏ giấy, callback/result/file, restart/unplug/permission |
| Candidate comparison | Chưa đo | camera_desktop và flutter_ffi_uvc cùng máy/camera/resolution; latency/stability/CPU/memory |
| Detection FPS target | Chưa đo Windows | Pre-recorded hoặc synthetic trên kiosk; >=10 FPS |
| Preview latency / CPU / capture latency | Chưa đo | <=100 ms / <=25% một core / <=300 ms; cần timestamp/counter và log profiler |
| 4K / DPI / orientation | Chưa thử | 100/150/200% DPI, full-resolution quad/crop và native texture alignment |
| Release no-op mechanism | Không áp dụng cho cơ chế có điều kiện | Không có no-op switch; start luôn mở camera ở debug và release. Camera release vẫn phải kiểm tra thật |

Không chọn backend default trước khi có phép đo. Root package không hard-depend
candidate nào; example chọn UVC thử nghiệm một cách tường minh. Cả hai adapter
có thể thay qua FrameSource. UVC đang copy full RGBA rồi downsample trong Dart,
cần profiling/native downsampling để xác nhận anti-lag; chưa chấp nhận gate hiệu
năng. Không tích hợp dartcv4; facade mặc định pure Dart giữ sàn SDK.

## Accessibility và Nielsen

- Đối tượng bắt buộc là example Windows đã build có preview/warning/result.
  Hiện mới có widget tests cho text, result, Esc và reduced-motion feedback.
- Windows accessibility inspection report: **chưa có**. Chưa có số critical,
  serious, moderate hoặc minor; không ghi 0 khi chưa đo.
- axe trên web: không áp dụng vì chỉ Windows desktop, không có web build.
  Phải thay bằng Windows Accessibility Insights / Inspect + Narrator và log.
- Lighthouse: **not applicable** vì không có web example. Báo cáo thay thế
  Windows accessibility inspection còn thiếu.
- [nielsen_review.md](nielsen_review.md): đủ 10 dòng, hiện đều Không đạt vì chưa
  review đúng bản Windows. Không suy ra pass từ source hoặc widget rendering.
- Cần đo contrast >=4.5:1 trên overlay/toolbar/result, focus thấy rõ, toàn bộ
  controls dùng bàn phím được, Esc đóng result và Windows reduced motion.

## Review tài liệu và package

- Đã đọc lại README/CHANGELOG sau implementation và ghi rõ trạng thái thử nghiệm,
  Windows x64 only, SDK floor, camera permission, giới hạn performance và dependencies.
- SECURITY ghi dữ liệu nhạy cảm, caller-controlled directory, không telemetry,
  không log nội dung ảnh, giới hạn xóa bộ nhớ và temporary file của adapter desktop.
- platforms/limitations phân biệt runtime guard với thứ cần máy Windows chứng minh.
- `.pubignore` loại docs/progress và đặc tả nội bộ; `publish_to: none` ngăn publish
  nhầm bản chưa bàn giao. Tên package được kiểm tra ở
  [dependency-metadata.txt](logs/dependency-metadata.txt), chưa đăng ký/publish.
- STATUS không đánh dấu Xong phase thiếu exit criteria Windows.
- Không có hợp đồng đăng nhập/credentials trong đặc tả ngoài một dòng integration
  “Login”; example là local kiosk có Bắt đầu, chưa có authentication.

## Phiên bản thật của các SDK đã chạy

### Flutter 3.32.8 — Linux, không phải Windows

```text
Flutter 3.32.8 • channel stable • https://github.com/flutter/flutter.git
Framework • revision edada7c56e (1 year, 3 months ago) • 2025-07-25 14:08:03 +0000
Engine • revision ef0cd00091 (1 year, 3 months ago) • 2025-07-24 12:23:50 -0700
Tools • Dart 3.8.1 • DevTools 2.45.1
```

### Flutter 3.41.9 — Linux, không phải Windows

```text
Flutter 3.41.9 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 00b0c91f06 (6 months ago) • 2026-04-29 10:03:19 -0700
Engine • hash 9161402dc0e134b3fb5adee5046b6e84b1a5e1c1 (revision 42d3d75a56) (5 months ago) • 2026-04-28 17:31:55.000Z
Tools • Dart 3.11.5 • DevTools 2.54.2
```

### Flutter 3.47.7 — Linux, không phải Windows

```text
Flutter 3.47.7 • channel stable • https://github.com/flutter/flutter.git
Framework • revision abaf9c5237 (2 weeks ago) • 2026-10-08 09:51:21 -0700
Engine • hash d8a2d6c768c334d53e16277f837970ffa1e2de81 (revision deb287481e) (15 days ago) • 2026-10-07 17:09:12.000Z
Tools • Dart 3.13.5 • DevTools 2.60.0
```

## Cấu hình cloud

Đã lưu draft `install_script` gọi `tool/bootstrap_cloud.sh` và `start_skill`
cho workflow coding/synthetic tests Linux bằng SDK/cache tại `/workspace`.
Không thêm secrets, không thay network policy hiện có. Draft không chạy lệnh,
không publish snapshot và không cung cấp Windows runner. Người dùng review/save
trong environment settings rồi Publish khi muốn tái sử dụng snapshot này.
