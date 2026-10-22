# Đặc Tả Kỹ Thuật Chi Tiết (AI-Coding Blueprint): Package `windows_doc_capture`

> **Mục đích tài liệu:** Đây là Engineering Specification ở cấp độ thực thi
> (Implementation-ready) để AI Coding Agent và lập trình viên xây dựng một
> Flutter package **chỉ hỗ trợ Windows x64** cho kiosk chụp giấy tờ.
>
> Package cung cấp: preview camera realtime, phát hiện giấy tờ (A4 / ID card),
> cảnh báo lệch khung / mờ / mất góc / quá tối / quá sáng **trước khi chụp**,
> tự động chụp khi giấy tờ ổn định, crop / perspective-correct đúng vùng giấy
> tờ, trả ảnh qua callback hoặc file, và đảm bảo không lag preview.
>
> **Cổng bàn giao:** Không được báo “xong” khi chưa đạt **mục 9 — Chuẩn
> Handover**. Mục 9 thắng các mục trước nếu có lệch về platform, SDK, test
> matrix hoặc cách viết tài liệu.
>
> **Phạm vi platform:** Windows x64 only. Không hỗ trợ Android, iOS, macOS,
> Linux, Web trong phiên bản này. Không được ghi `N/A` cho Windows.
>
> **SDK bắt buộc:** Flutter `3.32.8` (Dart `3.8.1`), Flutter `3.41.9`
> (Dart `3.11.5`), và Flutter stable mới hơn tại thời điểm chạy. Không được
> nâng sàn SDK để né lỗi tương thích.

## 1. Tổng quan Dự án & Giá trị Cốt lõi

### 1.1. Bài toán

Kiosk Windows cần chụp giấy tờ tự động, không có nhân viên vận hành. Người
dùng đặt tờ A4 hoặc ID card trước camera. Hệ thống phải:

1. Preview camera mượt, không lag.
2. Phát hiện giấy tờ trong khung hình.
3. Cảnh báo ngay trên preview nếu giấy tờ lệch khung, bị mờ, mất góc, quá
   tối hoặc quá sáng.
4. Tự động chụp khi giấy tờ đã ổn định và chất lượng đạt ngưỡng.
5. Crop đúng phần giấy tờ, perspective-correct về hình chữ nhật.
6. Trả ảnh đã crop qua callback và/hoặc ghi file.
7. Chạy liên tục trong môi trường kiosk mà không rò rỉ tài nguyên.

### 1.2. Non-goals

- Không OCR; đầu ra là ảnh, không phải text.
- Không nhận diện loại giấy tờ bằng ML trong bản đầu. Phân loại A4 / ID card
  dựa trên aspect ratio và hình học, có thể mở rộng sau.
- Không hỗ trợ camera IP / RTSP; chỉ camera local qua Media Foundation.
- Không hỗ trợ Windows ARM trong bản handover đầu tiên; nếu có test thì ghi
  riêng, không được tuyên bố support.
- Không hỗ trợ multi-camera đồng thời.

### 1.3. Người dùng & môi trường

| Vai trò | Nhu cầu |
| :--- | :--- |
| Kiosk end-user | Đặt giấy tờ, nhận phản hồi trực quan, không cần thao tác kỹ thuật |
| Kiosk operator / IT | Cài package, cấu hình camera, đảm bảo camera permission và firewall |
| Developer tích hợp | API rõ ràng, callback ổn định, có example chạy được |
| QA | Có thể test bằng ảnh/frame pre-recorded, có log latency/FPS |

## 2. Kiến trúc Hệ thống & Tech Stack

### 2.1. Tầng camera

Package phải hỗ trợ preview latency thấp trên Windows. Agent phải **đo thực
nghiệm** ít nhất hai candidate sau trên Windows thật, rồi chọn một làm default:

| Candidate | Điểm mạnh | Điểm cần kiểm tra |
| :--- | :--- | :--- |
| `camera_desktop` | Media Foundation / IMFCaptureEngine, Direct3D 11 texture, FFI zero-copy frame delivery, real-time image stream | Độ ổn định với nhiều UVC camera, latency thực tế |
| `flutter_ffi_uvc` | Media Foundation, FlutterTexture preview, `copyLatestFrame()` lấy frame bytes | Latency khi copy frame, độ ổn định driver |

**Luật:**

- Không hard-code dependency trước khi đo. Kết quả đo phải ghi vào
  `docs/progress/STATUS.md`.
- Preview **không được copy pixel qua Dart isolate** cho luồng hiển thị.
  Nếu backend trả frame bytes, phải đưa vào texture tại native layer hoặc
  dùng cơ chế zero-copy/transferable buffer.
- Phải có abstraction `FrameSource` để có thể đổi backend mà không sửa
  detection/capture pipeline.

### 2.2. Tầng detection & quality

Không được hard-depend `dartcv4` bản mới nếu bản đó yêu cầu Dart SDK >
`3.8.1`, vì sẽ phá sàn Flutter `3.32.8`. Thiết kế bắt buộc:

```dart
abstract class DocumentDetector {
  Future<DetectionResult> detect(FrameBuffer frame);
  void dispose();
}
```

Các backend được phép:

1. **Pure Dart / FFI tối giản**: grayscale → Gaussian blur → Canny/adaptive
   threshold → contour → quadrilateral fitting. Đây là fallback bắt buộc
   phải build được trên Flutter `3.32.8`.
2. **`dartcv4`**: chỉ dùng qua conditional import / facade nếu SDK hiện tại
   resolve được. Không được làm hỏng build trên `3.32.8`.
3. **`flutter_document_capture`**: chỉ tham khảo API design; không mặc định
   phụ thuộc vì Windows support chưa được xác nhận trong tài liệu công khai.
4. `flutter_edge_detection`: **không dùng** vì không hỗ trợ Windows.

### 2.3. Tầng cảnh báo & auto-capture

- `DocumentQualityAnalyzer` chạy trong **isolate riêng**, nhận frame đã
  downsample, trả `QualityReport`.
- `AutoCaptureController` là state machine:
  `idle → detecting → stable → capturing → cooldown`.
- `PreviewWarningStream` expose `Stream<PreviewWarning>`.
- Mỗi warning phải có `type`, `message`, `severity`; UI không được chỉ dựa
  vào màu.

### 2.4. Tầng output

- `CapturedDocument` chứa:
  - `originalJpeg`: full frame.
  - `croppedJpeg`: ảnh đã perspective-correct.
  - `quad`: 4 corner trong coordinate của full frame.
  - `blurScore`, `coverageRatio`, `capturedAt`.
  - `savedPath`: null nếu không cấu hình `saveDirectory`.
- Callback auto-capture: `void Function(CapturedDocument)? onAutoCapture`.
- Manual capture: `Future<CapturedDocument?> captureNow()`.

## 3. Cấu trúc Thư mục Chuẩn

```text
windows_doc_capture/
├── lib/
│   ├── windows_doc_capture.dart          # Public API
│   └── src/
│       ├── camera/
│       │   ├── camera_controller.dart
│       │   ├── frame_source.dart
│       │   └── camera_backend.dart       # Facade đổi backend
│       ├── detection/
│       │   ├── document_detector.dart    # Interface
│       │   ├── detector_facade.dart      # Conditional import
│       │   ├── quality_analyzer.dart
│       │   └── detection_result.dart
│       ├── capture/
│       │   ├── auto_capture_controller.dart
│       │   ├── crop_pipeline.dart
│       │   └── captured_document.dart
│       ├── warnings/
│       │   └── preview_warning.dart
│       └── platform/
│           └── windows_ffi/              # Native helpers nếu cần
├── windows/                              # CMake native plugin nếu cần
├── example/
├── test/
├── docs/
│   ├── progress/
│   │   ├── STATUS.md
│   │   ├── HANDOVER.md
│   │   └── nielsen_review.md
│   ├── limitations.md
│   └── platforms.md
├── pubspec.yaml
├── README.md
├── CHANGELOG.md
└── SECURITY.md
```

## 4. Đặc tả Dữ liệu & Public API

### 4.1. Public API

```dart
class WindowsDocCapture {
  Future<void> start({
    String? deviceId,
    ResolutionPreset preset = ResolutionPreset.high,
    bool enableAutoCapture = true,
    String? saveDirectory,
    void Function(CapturedDocument)? onAutoCapture,
  });

  Future<void> stop();

  Future<CapturedDocument?> captureNow();

  Stream<PreviewWarning> get warnings;

  Widget buildPreview();

  set autoCaptureEnabled(bool value);

  Future<List<CameraDevice>> listDevices();
}
```

### 4.2. `CapturedDocument`

```dart
class CapturedDocument {
  final Uint8List originalJpeg;
  final Uint8List croppedJpeg;
  final List<Offset> quad;
  final double blurScore;
  final double coverageRatio;
  final DateTime capturedAt;
  final String? savedPath;
}
```

### 4.3. `PreviewWarning`

```dart
enum WarningType {
  noDocument,
  outOfFrame,
  blur,
  tilt,
  tooDark,
  tooBright,
}

class PreviewWarning {
  final WarningType type;
  final String message;
  final double severity; // 0.0 – 1.0
}
```

### 4.4. `DetectionResult`

```dart
class DetectionResult {
  final bool hasDocument;
  final List<Offset>? quad;
  final double coverageRatio;
  final double tiltAngle;
  final double edgeMargin;
  final double blurScore;
  final double brightnessScore;
}
```

## 5. Thuật toán Detection, Warning & Auto-capture

### 5.1. Pipeline mỗi frame phân tích

1. Downsample frame về chiều rộng tối đa `640 px` (cấu hình được).
2. Grayscale.
3. Gaussian blur `5x5`.
4. Canny hoặc adaptive threshold.
5. Tìm contour; lọc contour có 4 đỉnh và diện tích ≥ 5% frame.
6. Tính:
   - `coverageRatio = area(quad) / area(frame)`
   - `tiltAngle = max deviation từ 90°`
   - `edgeMargin = min distance từ quad edge tới frame edge`
7. Tính `blurScore` trên ROI giấy tờ bằng Laplacian variance hoặc Tenengrad.
8. Tính `brightnessScore` bằng mean luma + histogram clipping.

### 5.2. Warning rules

| Warning | Điều kiện |
| :--- | :--- |
| `noDocument` | Không có quad hợp lệ |
| `outOfFrame` | `edgeMargin < 0.02` hoặc quad chạm biên |
| `blur` | `blurScore < blurThreshold` |
| `tilt` | `tiltAngle > 15°` (cấu hình được) |
| `tooDark` | mean luma < 0.2 |
| `tooBright` | mean luma > 0.85 hoặc clipping ratio > ngưỡng |

### 5.3. Auto-capture trigger

Chỉ trigger khi **tất cả** điều kiện sau giữ liên tục `stableFrameCount`
frame (mặc định `8`, cấu hình được):

- `hasDocument == true`
- `coverageRatio >= 0.15`
- `edgeMargin >= 0.02`
- `tiltAngle <= 15°`
- `blurScore >= blurThreshold`
- `brightness` trong `[0.2, 0.85]`

Nếu fail bất kỳ điều kiện nào: reset stable counter và emit warning tương ứng.

**Bắt buộc UX:** Trước khi auto-capture, phải có feedback trực quan (倒计时
hoặc viền đổi màu) ít nhất `500 ms`. Không được chụp “đột ngột” không báo.

### 5.4. Crop & perspective correction

1. Khi capture, lấy **full-resolution frame mới nhất**, không dùng frame
   downsampled của detection.
2. Map 4 corner từ detection coords sang full-resolution coords.
3. Dùng perspective transform + warp perspective để ra ảnh chữ nhật.
4. Encode JPEG quality 90 (cấu hình được).
5. Nếu `saveDirectory != null`, ghi file; luôn trả `Uint8List` trong callback.

## 6. Hiệu năng & Chống lag

| Ràng buộc | Ngưỡng | Cách đo |
| :--- | :--- | :--- |
| Preview latency | ≤ 100 ms | Timestamp camera → texture |
| Detection FPS | ≥ 10 FPS trên máy kiosk target | Benchmark trong example |
| Detect → capture end-to-end | ≤ 300 ms | Log trong `CapturedDocument` |
| CPU usage | ≤ 25% một core khi preview + detect | Task Manager / Process Explorer |
| Backpressure | Nếu detect queue > 1 frame, drop cũ giữ mới | Assert trong code |

**Luật bắt buộc:**

- Preview không đi qua Dart isolate để copy pixel.
- Detection isolate nhận frame qua `SendPort` dưới dạng transferable
  `TypedData`, hoặc copy tối đa một lần nếu SDK cũ không hỗ trợ.
- Không `await` tuần tự trong frame callback của camera.
- Auto-capture không được block preview thread.

## 7. SDK, Dependency & Platform Policy

### 7.1. `pubspec.yaml`

```yaml
environment:
  sdk: '>=3.8.0 <4.0.0'
  flutter: '>=3.32.8'

flutter:
  plugin:
    platforms:
      windows:
        pluginClass: WindowsDocCapturePlugin
```

- Không khai báo platform khác.
- `README` và `description` phải ghi rõ **Windows x64 only**.
- `dartcv4` chỉ được dùng qua facade/conditional import; không được làm
  `flutter pub get` fail trên `3.32.8`.
- `flutter analyze` phải xanh trên cả ba SDK ở mục 9.2.

### 7.2. Camera permission & môi trường

Windows không có runtime permission dialog như mobile. README phải ghi:

- Cần bật camera trong Windows Settings hoặc group policy.
- Nếu bị chặn, `start()` phải trả lỗi rõ ràng, không crash.
- Không tự động ghi log nội dung frame hoặc tên file chứa dữ liệu người dùng.

## 8. UI/UX cho Example & Kiosk

`example/` là Windows desktop app, phải có:

- Preview toàn màn hình.
- Overlay quad: xanh khi hợp lệ, cam khi warning.
- Warning text: “Đưa giấy tờ vào khung”, “Giấy tờ bị lệch”, “Ảnh bị mờ,
  giữ yên”, “Quá tối”, “Quá sáng”.
- Auto-capture feedback: viền/倒计时 trước khi chụp.
- Sau capture: hiển thị ảnh cropped + nút “Chụp lại”.
- Dev overlay có thể bật/tắt: preview FPS, detection FPS, latency.

**Ràng buộc accessibility:**

- Warning không chỉ dựa vào màu; phải có text/icon.
- Button có focus nhìn thấy, thao tác được bằng bàn phím.
- `Esc` đóng panel kết quả.
- Tôn trọng `prefers-reduced-motion`.

## 9. Chuẩn Handover

`docs/progress/HANDOVER.md` mở đầu bằng một dòng duy nhất:

```text
Handover: DAT
```

chỉ khi 9.1, 9.2, 9.3 và 9.4 đều `Đạt`. Ngược lại phải là:

```text
Handover: CHUA DAT
```

và liệt kê mục còn thiếu. Không có log thì ghi `Chưa đạt`, không ghi `Đạt`.

### 9.1. Build & Test Matrix

Chạy trong package và `example/` trừ khi ghi rõ.

| Hạng mục | Lệnh phải xanh | Runner | Bắt buộc |
| :--- | :--- | :--- | :--- |
| Analyze package | `flutter analyze` | Windows | ✅ |
| Analyze example | `flutter analyze` | Windows | ✅ |
| Unit / widget test | `flutter test` | Windows | ✅ |
| Build example | `flutter build windows` | Windows | ✅ |
| Integration real camera | Chạy example: Login → đặt giấy → auto capture → callback → file | Windows 真机/VM | ✅ |
| Detection FPS benchmark | Pre-recorded frames benchmark | Windows | ✅ |
| Release no-op test | Test `start()` không mở camera/socket khi release nếu có cơ chế tương tự | Windows | ✅ nếu áp dụng |

**Luật:**

- Chỉ có một platform bắt buộc: **Windows x64**. Không được ghi `N/A`.
- CI không có camera thật thì phải ghi log máy thật/VM vào `HANDOVER.md`;
  không được bỏ hẳn integration test.
- Còn một test đỏ trên Windows là handover trượt.
- Test detection/crop phải dùng **pre-recorded frames hoặc synthetic images**,
  không phụ thuộc camera cho unit test.

### 9.2. Test trên Flutter 3.32.8, 3.41.9 và mới hơn

| SDK | Dart đi kèm | Vai trò |
| :--- | :--- | :--- |
| Flutter `3.32.8` | `3.8.1` | Sàn. App cũ nhất còn nhận package |
| Flutter `3.41.9` | `3.11.5` | Bản pin giữa |
| Flutter stable mới nhất tại thời điểm chạy, phải `>` `3.41.9` | theo bản đó | “Hoặc mới hơn” |

Trên **mỗi** SDK phải làm:

1. `flutter pub get` trong package và `example/`.
2. `flutter analyze`.
3. `flutter test`.
4. `flutter build windows`.
5. Ghi `flutter --version` thật vào `docs/progress/HANDOVER.md`.
6. Không được ghi đè version cho đủ bảng.

Nếu `dartcv4` hoặc dependency nào không resolve trên `3.32.8`, phải sửa facade
hoặc bỏ dependency khỏi default path; **không được nâng sàn SDK** để né.

### 9.3. UI/UX: WCAG, axe, Nielsen, Lighthouse

Đối tượng đo là **example app đã build**, mở với preview + warning + result
panel. Không đo trang trống.

**WCAG 2.2 AA:**

- Text trên overlay và toolbar đạt contrast ≥ 4.5:1.
- Warning có text/icon, không chỉ màu.
- Button/close panel có focus nhìn thấy và thao tác bàn phím được.
- `Esc` đóng panel kết quả.
- `prefers-reduced-motion: reduce` thì giảm/tắt animation.
- `html`/app language đúng `vi` hoặc `en` nếu example có web build; Windows
  desktop vẫn phải có text rõ ràng.

**axe:**

- Chạy `@axe-core/playwright` hoặc tương đương trên example nếu example có
  web build; nếu chỉ Windows desktop, dùng accessibility inspection của
  Windows và ghi log.
- **0 critical, 0 serious**. Moderate/minor phải có dòng trong
  `HANDOVER.md`: sửa hoặc lý do giữ lại.
- Report phải lưu path trong `HANDOVER.md`.

**Nielsen 10 heuristics:** file `docs/progress/nielsen_review.md`, mỗi
heuristic một dòng `Đạt` / `Không đạt` kèm màn đã xem. `Không đạt` thì chưa
handover.

| # | Heuristic | Điều kiện Đạt |
| :--- | :--- | :--- |
| 1 | Visibility of system status | Thấy camera status, warning, FPS/latency nếu bật dev overlay |
| 2 | Match system / real world | Warning dùng ngôn ngữ người dùng, không thuật ngữ CV |
| 3 | User control and freedom | Có “Chụp lại”, đóng panel, tắt auto-capture |
| 4 | Consistency and standards | Cùng icon/màu cho cùng warning, cùng vị trí nút |
| 5 | Error prevention | Auto-capture chỉ trigger khi stable; có feedback trước khi chụp |
| 6 | Recognition rather than recall | Legend màu + text warning |
| 7 | Flexibility and efficiency | Manual capture + auto capture; device selection |
| 8 | Aesthetic and minimalist | Overlay không che kín giấy tờ; warning gọn |
| 9 | Recover from errors | Camera lỗi / permission bị chặn có thông báo và next step |
| 10 | Help and documentation | Footer/README trỏ tới hướng dẫn và known limitations |

**Lighthouse:** nếu example có web build thì Accessibility ≥ 95, Best
Practices ≥ 95, Performance ≥ 80; SEO không chặn. Nếu chỉ Windows desktop,
ghi rõ “not applicable” trong `HANDOVER.md` và thay bằng Windows
accessibility inspection log.

### 9.4. Review và cập nhật tài liệu

Tài liệu chia hai loại. Không trộn.

**Ngắn hạn — tiến độ nội bộ, không publish:**

| File | Nội dung được phép |
| :--- | :--- |
| `docs/progress/STATUS.md` | Bảng phase và platform: `Xong` / `Đang làm` / `Chưa làm`. Có ngày cập nhật. Không viết hướng dẫn cài đặt |
| `docs/progress/HANDOVER.md` | Checklist 9.1–9.4, `flutter --version`, đường dẫn log, axe, benchmark |
| `docs/progress/nielsen_review.md` | Biên bản heuristic, ngày review |

Mỗi phase xong phải sửa `STATUS.md` trong cùng thay đổi. `docs/progress/`
không được đưa vào package publish như tài liệu người dùng.

**Dài hạn — người dùng và người bảo trì:**

| File | Nội dung |
| :--- | :--- |
| `README.md` | Cài đặt, `start()` snippet, Windows x64 only, camera permission, host/firewall không áp dụng, latency/FPS kỳ vọng, known limitations |
| `CHANGELOG.md` | Keep a Changelog. `## [Unreleased]` phải có thay đổi người dùng thấy được; không bịa version |
| `SECURITY.md` | Không telemetry, không log frame content, `saveDirectory` do caller kiểm soát, redact dữ liệu nhạy cảm |
| `docs/platforms.md` | Bảng Windows x64: cái runtime bắt được và cái không bắt được; Windows ARM chưa support |
| `docs/limitations.md` | Non-goals đã biết: không OCR, không camera IP, không multi-camera, `dartcv4` conditional, v.v. |

**Luật review lúc handover:**

- Đọc lại README và CHANGELOG sau khi code đổi. Câu nào mô tả tính năng chưa
  có trong bản build thì xóa hoặc chuyển xuống `docs/limitations.md`.
- `STATUS.md` không được để phase đã merge ở trạng thái `Chưa làm`; phase
  chưa có test không được `Xong`.
- README không chứa bảng tiến độ. `STATUS.md` không chứa hướng dẫn publish.
- `CHANGELOG.md` của bản handover phải có `Unreleased` hoặc version sắp gắn.
  Để rỗng là trượt.

### 9.5. Định nghĩa “đã handover”

`docs/progress/HANDOVER.md` mở đầu bằng `Handover: DAT` chỉ khi:

- 9.1: mọi mục Windows có log/artifact path, không có test đỏ.
- 9.2: cả ba SDK có `flutter --version`, `analyze`, `test`, `build windows`
  xanh.
- 9.3: axe report + Nielsen review tồn tại, không có `Không đạt`; nếu
  Lighthouse không áp dụng thì có lý do rõ.
- 9.4: README/CHANGELOG/SECURITY/limitations/platforms đã review và khớp
  implementation.

Ngược lại phải là `Handover: CHUA DAT` kèm danh sách mục thiếu.

## 10. Lộ trình Triển khai cho AI Coding Agent

### Phase 1 — Skeleton & camera preview

- Tạo package structure, `pubspec.yaml`, example Windows app.
- Đo `camera_desktop` vs `flutter_ffi_uvc`; chọn backend default; ghi
  `STATUS.md`.
- Viết `CameraController` wrapper: `start/stop/buildPreview/listDevices`.
- Đảm bảo preview không copy pixel qua Dart isolate.
- **Exit criteria:** `flutter build windows` xanh; example preview realtime;
  latency đo được.

### Phase 2 — Detection & quality

- Viết `DocumentDetector` interface + default backend.
- Viết quality scoring: blur, brightness, coverage, tilt, edgeMargin.
- Detection chạy isolate, có backpressure drop-old-keep-new.
- Unit test với synthetic images / pre-recorded frames.
- **Exit criteria:** detection ≥ 10 FPS trên máy target; unit test xanh.

### Phase 3 — Warning & auto-capture

- Viết `PreviewWarning` stream.
- Viết `AutoCaptureController` state machine.
- Example UI overlay warning + feedback trước capture.
- **Exit criteria:** đặt giấy → warning biến mất → auto capture callback;
  bỏ giấy → không capture.

### Phase 4 — Crop & output

- Perspective transform + JPEG encode.
- `saveDirectory` file output + callback.
- **Exit criteria:** cropped image chỉ chứa giấy tờ; quad mapping đúng ở
  full resolution.

### Phase 5 — Hardening & handover

- Profiling latency/FPS/CPU; tối ưu đến mục 6.
- Test trên 3 SDK.
- Viết README/CHANGELOG/SECURITY/limitations/platforms.
- Chạy toàn bộ mục 9.

## 11. Câu hỏi mở & Rủi ro cần Agent trả lời

| # | Câu hỏi / Rủi ro | Cách xử lý bắt buộc |
| :--- | :--- | :--- |
| 1 | Chọn `camera_desktop` hay `flutter_ffi_uvc`? | Đo latency/ổn định trên Windows thật, ghi `STATUS.md` |
| 2 | `dartcv4` không resolve trên Flutter 3.32.8? | Dùng facade + pure Dart fallback; không nâng sàn SDK |
| 3 | Auto-capture trigger nhầm khi giấy đang di chuyển? | Stable frame count + feedback trước capture |
| 4 | 4K/DPI scaling làm lệch quad? | Test trên 4K; dùng cùng coordinate space; ghi log |
| 5 | Camera bị group policy chặn? | `start()` trả lỗi rõ; README hướng dẫn IT |
| 6 | CI không có camera thật? | Ghi log máy thật/VM vào `HANDOVER.md`; không bỏ integration |
| 7 | Package name có thể trùng? | Agent phải kiểm tra pub.dev trước khi tạo; nếu trùng, đề xuất tên khác và ghi lại |
| 8 | Có cần OCR / phân loại A4 vs ID card? | Bản đầu không; chỉ dùng aspect ratio/hình học; ghi limitations |

## 12. Phụ lục — Mức độ ưu tiên khi lệch đặc tả

Nếu có xung đột giữa các mục:

1. **Mục 9 — Handover** là cao nhất.
2. **Mục 7 — SDK/Platform policy** (Windows only, 3.32.8 floor) là thứ hai.
3. **Mục 6 — Performance/anti-lag** là thứ ba.
4. Các mục còn lại có thể điều chỉnh nếu có lý do kỹ thuật, nhưng phải ghi
   vào `STATUS.md` và `HANDOVER.md`.