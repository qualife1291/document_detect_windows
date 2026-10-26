Handover: CHUA DAT

# Bằng chứng bàn giao

Cập nhật log thứ tư (2026-10-26): sửa nhấp nháy bằng stream identity ổn định,
giữ ảnh qua 30 status/parent rebuilds. Hiển thị kết quả không upscale theo DPI,
preset high độc lập sampling, có chọn độ phân giải trong example. Windows/Linux
đạt ba SDK: 108 package, 6 UVC adapter, 7 example tests, benchmark/endurance và
Windows release build. Xem [review](FOURTH_LOG_REVIEW.md). Chưa xác nhận nét
quang học hoặc GPU/24–168 h trên thiết bị thật sau bản sửa này.

Cập nhật log treo GPU: đã thêm bitmap preview có backpressure/dispose, cấu hình
example nhẹ hơn, dừng camera trước result và evict ảnh result có giới hạn decode.
Windows/Linux đã đạt ba SDK: 108 package, 4 adapter UVC và 6 example tests,
hai benchmark và endurance. Xem [review log thứ ba](GPU_LOG_REVIEW.md).
Chưa xác minh GPU hang đã hết trên máy người dùng hoặc chạy 24/7.

Cập nhật crop theo debug_log_2: đã đạt 102 package tests, 3 example tests, hai
benchmark và endurance trên Windows/Linux ba SDK. Crop có margin mặc định 2%
và metadata góc thực tế; preview có cornerRadius tùy chỉnh. Xem [review crop](CROP_LOG_REVIEW.md).
Các sửa cadence/detection trước đó nằm trong [review log đầu](PHYSICAL_LOG_REVIEW.md).

Cập nhật diagnostics 2026-10-23: đã đạt Windows/Linux ba SDK với 76 package
tests (gồm 10 diagnostics tests), 3 example tests, benchmark và endurance.
Log bật trong debug, opt-in profile/release; timer/sink/redaction có regression tests.

Cập nhật hardening 2026-10-23: tối ưu/vòng đời đã đạt Windows SDK matrix
và Linux supplemental. Có thêm 5/8 MP, document/light, cancellation/dispose tests
và endurance ngắn trên đúng source. Chưa xác nhận camera thật hoặc 24/7.
Chi tiết: [review](HARDENING_REVIEW.md), [continuous operation](../continuous_operation.md).

Cập nhật preview 2026-10-23: đã thêm callback enum, previewStatus và overlay
bốn góc. Windows/Linux đã kiểm chứng suite mới, gồm detection khi tắt auto-capture,
quality enums, geometry contain/cover/fill/4K, expiry và callback lifecycle.
Độ khớp native texture trên camera thật vẫn cần operator xác nhận.

Chưa đạt mục 9.1 (camera thật/kiosk) và 9.3 (Windows accessibility/Nielsen).
Cloud machine là Linux x86_64; Windows build/test được chạy riêng trên GitHub
Actions Windows-2022 x64. Không suy ra camera thật hoặc deployment readiness
từ CI/synthetic tests.

| Gate | Trạng thái | Bằng chứng / phần thiếu |
| --- | --- | --- |
| 9.1 Build & Test Windows x64 | Chưa đạt | Analyze/test/build đã đạt ba SDK; thiếu camera thật, kiosk metrics và 4K/DPI |
| 9.2 Ba SDK trên Windows | Đạt cho package/example | Pub get/analyze/test/build x64 release và version thật có log ở bảng dưới |
| 9.3 Accessibility / Nielsen | Chưa đạt | Thiếu compiled-app inspection, contrast, critical/serious counts, keyboard/reduced motion trên desktop và 10 heuristics |
| 9.4 Tài liệu | Đạt — source/evidence review | README/CHANGELOG/SECURITY/platforms/limitations khớp implementation, tách giới hạn/tiến độ |

## Windows x64 SDK matrix đã chạy

Nguồn được kiểm tra: commit `7d789ded065afeab591f3e4761de49b3bb6458df`.
[Workflow xác nhận cuối](https://github.com/qualife1291/document_detect_windows/actions/runs/40262146792)
đã chạy package/example thành công trên cả ba SDK. Mỗi SDK có 108 package tests,
7 example widget tests và 2 benchmark tests (detector và snapshot processing). Không skip,
disable hoặc expected-failure trong các suite này. Các artifact logs được tải
qua GitHub API và giữ nguyên nội dung.

| Flutter | pub get package/example | analyze package/example | Package / example / benchmark | Build example | Synthetic mean / FPS | Log |
| --- | --- | --- | --- | --- | --- | --- |
| 3.32.8 | Đạt / Đạt | Đạt / Đạt | 108 / 7 / 2 đạt | Đạt x64 release | 51.39 ms / 19.46 FPS | [logs](logs/windows-3.32.8/) |
| 3.41.9 | Đạt / Đạt | Đạt / Đạt | 108 / 7 / 2 đạt | Đạt x64 release | 48.60 ms / 20.58 FPS | [logs](logs/windows-3.41.9/) |
| 3.47.8 | Đạt / Đạt | Đạt / Đạt | 108 / 7 / 2 đạt | Đạt x64 release | 59.98 ms / 16.67 FPS | [logs](logs/windows-3.47.8/) |

UVC adapter cũng pub get/analyze và 6 tests đạt cả ba SDK trong cùng Windows jobs.
Toàn bộ ba Windows jobs đã đạt, gồm cả adapter camera_desktop trên 3.41.9
và stable. [ci-provenance.json](logs/ci-provenance.json) lưu source SHA, job/step
conclusions và artifact hashes. Source commit ở trên bao gồm regression tests
cho preview, callback dừng camera và đóng streams khi native stop báo lỗi.

Analyzer stable của lượt CI đầu phát hiện thiếu `await` trong `try/finally`
ở desktop snapshot decode. Đã sửa ở commit `47dd322`, kiểm tra lại thành công.
[diagnosed-desktop-analyze-stable.txt](logs/diagnosed-desktop-analyze-stable.txt)
giữ nguyên chẩn đoán cũ, không phải lỗi còn tồn tại. Không bỏ assertion/test
hoặc hạ analyzer severity để làm CI xanh.

Benchmark Windows dùng `flutter test` trên hosted VM, không phải release kiosk.
Nó không đo camera-to-texture latency, CPU, physical preview/composited FPS hoặc
end-to-end <=300 ms. Log camera do người dùng cung cấp đã ghi native delivered FPS gần 30;
chưa đối chiếu bằng profiler/camera-to-texture measurements. `CapturedDocument.processingTime` không bao gồm thời
gian chờ stable feedback.

## Linux supplemental

`tool/validate_linux.sh` đã chạy pub get/analyze/test cho package/adapter UVC/
example trên Flutter 3.32.8, 3.41.9, 3.47.7. Mỗi SDK đạt 108 package tests, 6 UVC adapter và 7 widget
tests, 2 benchmark tests. Log và version thật ở [3.32.8](logs/linux-3.32.8/),
[3.41.9](logs/linux-3.41.9/), [3.47.7](logs/linux-3.47.7/).
Không dùng các kết quả Linux để chứng minh native Windows runtime.

Khi đổi SDK 3.32.8 -> 3.41.9, cache shader cũ gây lỗi `Expected 1, got 0`,
lưu ở [diagnosed-sdk-cache-3.41.9.txt](logs/diagnosed-sdk-cache-3.41.9.txt).
Dọn generated artifacts bằng `flutter clean` trước mỗi SDK sửa được lỗi; các
log cuối là lượt chạy lại đã đạt. Tool caches chuyển sang `/workspace` bằng
cấu hình được hỗ trợ vì home read-only. TLS và artifact checksum vẫn bật.
Bootstrap đã chạy và chạy lại đạt, log
[bootstrap-repeat.txt](logs/bootstrap-repeat.txt).

## Windows x64 — các gate còn thiếu

| Hạng mục | Trạng thái | Bằng chứng cần bổ sung |
| --- | --- | --- |
| Real camera integration | Có log người dùng; chưa đủ case | example/integration_test/real_camera_test.dart: operator đặt/bỏ giấy, callback/result/file, unplug/restart/permission |
| Candidate comparison | Chưa đo | camera_desktop vs flutter_ffi_uvc cùng máy/camera/resolution: latency/stability/CPU/memory |
| Detection FPS kiosk target | Chưa đo | >=10 FPS trên kiosk; hosted VM synthetic không thay thế target |
| Preview latency / CPU / capture latency | Chưa đo | <=100 ms / <=25% một core / <=300 ms; timestamp và profiler evidence |
| 4K / DPI / orientation | Chưa thử | 100/150/200% DPI, full-resolution corners/crop, native texture alignment |
| Windows accessibility | Chưa inspect | Accessibility Insights / Inspect + Narrator trên app đã build có preview/warning/result |
| Release no-op mechanism | Không áp dụng cho cơ chế có điều kiện | Không có no-op switch; start mở camera ở debug và release. Release camera vẫn phải kiểm tra thật |

Chưa chọn backend default trước khi đo. Root không hard-depend candidate nào;
example chọn UVC thử nghiệm tường minh. UVC copy full RGBA rồi downsample trong
Dart, cần profiling/native downsampling để chấp nhận gate hiệu năng. Không có
dartcv4 dependency; facade mặc định pure Dart giữ nguyên SDK floor.

## Accessibility và Nielsen

- Đối tượng bắt buộc: example Windows đã build có preview/warning/result.
  Widget tests đạt trên Windows/Linux cho text, manual/result, Esc và feedback
  reduced-motion; chưa thay thế inspection ứng dụng desktop đã mở.
- Windows accessibility report: chưa có. Chưa có critical/serious/moderate/minor
  counts; không ghi 0 khi chưa đo.
- axe web: không áp dụng vì không có web build; cần Windows inspection thay thế.
- Lighthouse: **not applicable**, Windows desktop only. Report thay thế còn thiếu.
- [nielsen_review.md](nielsen_review.md) có 10 dòng Không đạt vì chưa review đúng
  bản Windows đang chạy, không suy ra pass từ source/widget tests.
- Cần đo contrast >=4.5:1, visible keyboard focus, tất cả controls dùng được
  bằng bàn phím, Esc đóng result, Windows reduced-motion được tôn trọng.

## Tài liệu và phạm vi

Đã đọc lại README/CHANGELOG sau implementation: Windows x64 only, SDK floor,
permission, experimental backend, mục tiêu hiệu năng chưa chứng nhận. SECURITY
nêu dữ liệu nhạy cảm, caller-controlled save directory, không telemetry/log nội
dung ảnh, giới hạn secure erasure và temporary file của desktop adapter.
platforms/limitations phân biệt runtime guard và kiểm chứng thực nghiệm.
`.pubignore` loại docs/progress/ và đặc tả; `publish_to: none` chặn publish nhầm.
Tên package kiểm tra pub.dev ở [dependency-metadata.txt](logs/dependency-metadata.txt),
chưa đăng ký/publish. STATUS không đánh dấu Xong phase thiếu exit criteria.

Spec chỉ nhắc “Login” trong một dòng integration, không có hợp đồng xác thực;
example local có Bắt đầu, không triển khai authentication.

## Phiên bản thật trên Windows

### Windows — Flutter 3.32.8

```text
Flutter 3.32.8 • channel stable • https://github.com/flutter/flutter.git
Framework • revision edada7c56e (1 year, 3 months ago) • 2025-07-25 14:08:03 +0000
Engine • revision ef0cd00091 (1 year, 3 months ago) • 2025-07-24 12:23:50 -0700
Tools • Dart 3.8.1 • DevTools 2.45.1
```

### Windows — Flutter 3.41.9

```text
Flutter 3.41.9 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 00b0c91f06 (6 months ago) • 2026-04-29 10:03:19 -0700
Engine • hash 9161402dc0e134b3fb5adee5046b6e84b1a5e1c1 (revision 42d3d75a56) (5 months ago) • 2026-04-28 17:31:55.000Z
Tools • Dart 3.11.5 • DevTools 2.54.2
```

### Windows — Flutter 3.47.8

```text
Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 737ba8f885 (3 days ago) • 2026-10-22 21:37:31 -0700
Engine • hash dfd2e6cb7d319db05e3bf1503f3e2ac60f6288a2 (revision cf636b1dfb) (2 days ago) • 2026-10-23 02:13:38.000Z
Tools • Dart 3.13.7 • DevTools 2.60.0
```

## Cấu hình cloud

Đã lưu draft `install_script` gọi `tool/bootstrap_cloud.sh` và `start_skill`
cho coding/synthetic tests Linux, ba SDK/cache tại `/workspace`. Không thêm
secrets, không đổi network policy. Draft không execute/publish snapshot hoặc
cung cấp camera. Người dùng review/save trong environment settings rồi Publish
để tái sử dụng snapshot. GitHub Actions đã tạo được Windows build evidence
riêng; physical-camera/accessibility gates vẫn cần máy phù hợp.
