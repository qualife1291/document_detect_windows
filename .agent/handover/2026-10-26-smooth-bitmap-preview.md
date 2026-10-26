---
status: done
slug: smooth-bitmap-preview
updated: 2026-10-26
---

# Handover — smooth-bitmap-preview

## Kết quả

Đã đọc log lần 5 và tách target bitmap ~15 FPS khỏi analysis ~5 FPS để giảm cảm
giác chậm, giữ upstream backpressure và bộ nhớ có giới hạn. Source a9e29c4.
Đây là task source đã kiểm chứng; FPS/latency/CPU trên camera thật sau sửa chưa đo.

## Đối chiếu đặc tả

- File: specs/smooth-bitmap-preview.md.
- Khớp: cached streams riêng, shared readback, readiness theo session, pause khi
  capture/teardown, cost backoff và metadata riêng; crop/quality/native plugin không đổi.
- Lệch đã duyệt: không có.
- Lệch chưa duyệt: không có. Governance có commit/handover riêng trước task này.

## Đã làm

- Review 433 events/~420 s, 6/6 success; stream thực tế 1280×720 dù veryHigh.
- BitmapPreviewDemand chỉ báo readiness, không giữ pixels/callback/task queue.
- PreviewSamplingSource là optional, không bắt custom FrameSource cũ đổi method.
- Một copy/downsample phục vụ hai consumers khi cùng cần; extra preview bị chặn
  khi decoder busy/unmount/capture và tự backoff theo sampling cost EWMA.
- Health phân biệt offered FPS/age/cost với native delivery/analysis; không gọi đó
  là displayed FPS hoặc hardware capture timestamp.
- Example DOC_CAPTURE_PREVIEW_FPS 5–20, mặc định 15; có thể đặt 5 để so sánh cũ.

## Chưa làm

Không còn mục source trong scope. Chưa retest phiên bản mới trên camera người dùng.

## Cách chạy

- Trong example: flutter run -d windows --profile --dart-define=DOC_CAPTURE_LOGS=true.
- So sánh trước: thêm --dart-define=DOC_CAPTURE_PREVIEW_FPS=5, giữ nguyên camera/mode.
- Theo dõi bitmapOfferedFps, frameSamplingMeanMs/MaxMs, bitmapLastOfferAgeMs,
  nativeDeliveredFps và recentAnalysisFps; giữ cả engine errors trong log copy.

## Test sẵn có

- Trước: CI 40262146792 của runtime 7d789de, 108/6/7 tests và Windows build pass.
- Sau: CI 40267546967 source a9e29c4, 110 package/9 UVC/7 example tests pass
  trên Windows 3.32.8/3.41.9/3.47.8, hai benchmark/endurance 60 s và release build.
- Linux 3.32.8/3.41.9/3.47.7 đạt cùng suite/analyze và endurance 30 s; optional
  desktop analyzer đạt SDK đủ điều kiện. Format stable 49 files/0 changes.

## Test đã chạy

- PV-01: fake camera + widget: preview offers >1.5× analysis, counters riêng,
  shared immutable frames không nhân đôi copy; snapshot giữ negotiated size.
- PV-02: decoder gate, pause, unmount, restart/new handle và late image disposal;
  các regression stream identity/30 rebuilds/no-paint disposal/DPI giữ nguyên.
- PV-03: controller predicate false trong capture, true khi xong, null sau stop/dispose.
- PV-04: readback synthetic 60 ms làm backoff ≥240 ms; health delta metrics tách
  analysis/native, không pixels/PII. Không suy ra CPU budget tổng app.
- PV-05: local/full matrix pass. Bằng chứng docs/progress/logs/fifth-log-followup/,
  logs/windows-<sdk>/, logs/linux-<sdk>/ và logs/ci-provenance.json.
- CI: https://github.com/qualife1291/document_detect_windows/actions/runs/40267546967.

## Test không chạy

Physical composited FPS, sensor-to-screen latency, native CPU/GPU/VRAM, 5/8 MP
hardware và 24–168 h sau sửa: không có camera/kiosk Windows thật trong cloud.
Không gắn pass cho các gate đó từ fake timing test hoặc log trước bản sửa.

## Quyết định đã ghi vào nhớ dài hạn

D-005 — preview cadence độc lập và upstream demand trước readback.
ARCHITECTURE đã cập nhật luồng sampling/health; các giới hạn production giữ nguyên.

## Rủi ro và nợ

Native readback vẫn copy full RGBA trên UI isolate; backoff chỉ giảm phần extra
preview và không chặn được native call/driver đã wedged. Bitmap vẫn dùng Flutter
renderer/GPU; GPU loss có thể cần restart app. Overlay/enum giữ analysis cadence,
không tự đoán quad giữa reports. Mode veryHigh không ép camera có 5/8 MP.
Gate sản phẩm docs/progress/HANDOVER.md vẫn CHUA DAT.

## File đã đụng

lib/src/camera/{camera_controller,frame_source}.dart,
lib/src/preview/rgba_camera_preview.dart,
lib/src/diagnostics/capture_diagnostics.dart,
adapters/windows_doc_capture_uvc/{lib,test}/, example/lib/main.dart,
test/{controller,diagnostics,rgba_preview}_test.dart, README.md, CHANGELOG.md,
docs/continuous_operation.md, docs/progress/fifth-log-review.md,
specs/smooth-bitmap-preview.md, .agent/memory/ và evidence/handover.

## Agent sau đọc gì

1. AGENTS.md, specs/smooth-bitmap-preview.md và docs/progress/fifth-log-review.md.
2. .agent/memory/long-term/ARCHITECTURE.md, DECISIONS.md và CONVENTIONS.md.
3. docs/progress/HANDOVER.md để phân biệt task done và readiness sản phẩm.
