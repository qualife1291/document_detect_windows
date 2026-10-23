Handover: CHUA DAT

# Bằng chứng bàn giao

Cập nhật diagnostics 2026-10-23: log debugPrint đang được kiểm tra.
Các bảng source/CI bên dưới vẫn là baseline hardening `de48bba`, chưa là
bằng chứng của thay đổi diagnostics mới.

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

Nguồn được kiểm tra: commit `de48bba957e3d3646ee8537b32728959f803739b`.
[Workflow xác nhận cuối](https://github.com/qualife1291/document_detect_windows/actions/runs/39890972282)
đã chạy package/example thành công trên cả ba SDK. Mỗi SDK có 66 package tests,
3 example widget tests và 1 benchmark test (30 ảnh synthetic + 5 warmup). Không skip,
disable hoặc expected-failure trong các suite này. Các artifact logs được tải
qua GitHub API và giữ nguyên nội dung.

| Flutter | pub get package/example | analyze package/example | Package / example / benchmark | Build example | Synthetic mean / FPS | Log |
| --- | --- | --- | --- | --- | --- | --- |
| 3.32.8 | Đạt / Đạt | Đạt / Đạt | 66 / 3 / 1 đạt | Đạt x64 release | 56.54 ms / 17.69 FPS | [logs](logs/windows-3.32.8/) |
| 3.41.9 | Đạt / Đạt | Đạt / Đạt | 66 / 3 / 1 đạt | Đạt x64 release | 58.28 ms / 17.16 FPS | [logs](logs/windows-3.41.9/) |
| 3.47.7 | Đạt / Đạt | Đạt / Đạt | 66 / 3 / 1 đạt | Đạt x64 release | 57.73 ms / 17.32 FPS | [logs](logs/windows-3.47.7/) |

UVC adapter cũng pub get/analyze đạt cả ba SDK trong cùng Windows jobs.
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
end-to-end <=300 ms. Counter native delivered FPS trong example chưa được kiểm
chứng với camera thật. `CapturedDocument.processingTime` không bao gồm thời
gian chờ stable feedback.

## Linux supplemental

`tool/validate_linux.sh` đã chạy pub get/analyze/test cho package/adapter UVC/
example trên Flutter 3.32.8, 3.41.9, 3.47.7. Mỗi SDK đạt 66 package tests, 3 widget
tests, 1 benchmark test. Log và version thật ở [3.32.8](logs/linux-3.32.8/),
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
| Real camera integration | Chưa chạy | example/integration_test/real_camera_test.dart: operator đặt/bỏ giấy, callback/result/file, unplug/restart/permission |
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

### Windows — Flutter 3.47.7

```text
Flutter 3.47.7 • channel stable • https://github.com/flutter/flutter.git
Framework • revision abaf9c5237 (2 weeks ago) • 2026-10-08 09:51:21 -0700
Engine • hash d8a2d6c768c334d53e16277f837970ffa1e2de81 (revision deb287481e) (15 days ago) • 2026-10-07 17:09:12.000Z
Tools • Dart 3.13.5 • DevTools 2.60.0
```

## Cấu hình cloud

Đã lưu draft `install_script` gọi `tool/bootstrap_cloud.sh` và `start_skill`
cho coding/synthetic tests Linux, ba SDK/cache tại `/workspace`. Không thêm
secrets, không đổi network policy. Draft không execute/publish snapshot hoặc
cung cấp camera. Người dùng review/save trong environment settings rồi Publish
để tái sử dụng snapshot. GitHub Actions đã tạo được Windows build evidence
riêng; physical-camera/accessibility gates vẫn cần máy phù hợp.
