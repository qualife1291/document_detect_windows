---
status: done
slug: kiosk-preview-integration
updated: 2026-10-29
---

# Handover — kiosk-preview-integration

User gửi shared CameraPlatform widget, flow GetX ID và upload nhiều chứng từ.
Đã chuẩn bị sample + guide theo specs/kiosk-preview-integration.md. Source
1f55c45433467ced173c26f8e4ad925c574770d9 đã push main. Phần sau chỉ docs/evidence.

## Kết quả

example/lib/integration/camera_preview_widget.dart là file copyable độc lập GetX.
Giữ optional CameraPreviewController/capture()/Uint8List callback; một callback,
ưu tiên widget nếu có. Batch mặc định giữ session và removal latch (giống old
widget giữ preview); ID chọn single để stop + release hook trước callback.
Hardware select/acquire/configure/release là hook; callback/late capture/acquire
được guard; stop ngay khi hidden, active=false hoặc shutdown. Remount cùng
controller await cleanup cũ. Không file ảnh, image history hoặc global cache clear.
Bỏ old fixed crop/zoom/mirror rõ trong guide; camera_windows ID không mặc định
khớp UVC. Controller mỗi view ổn định; captureFactory tạo owned capture mới.
Guide docs/integration/kiosk-getx.md có wiring hai flow, navigation/dialog/upload
await stop, onClose fallback, limits cho host giữ/encode ảnh. Không đổi backend/
AI nghiệp vụ của kiosk; services riêng chưa có source nên không giả định control.

## Kiểm chứng

Windows CI 40730610952 (https://github.com/qualife1291/document_detect_windows/actions/runs/40730610952) success,
Flutter 3.32.8/3.41.9/3.47.8: 117 root, 11 UVC, 33 example tests/SDK;
analyze, 3 benchmarks, native sampler CTest, endurance mô phỏng 60 s và release build.
Stable format 60 và host riêng chép widget cùng camera_windows 0.2.6+4/original UVC/
internal UVC đạt ba DLL/license/registration. Linux 3.32.8/3.41.9 example 33/analyze
có logs; stable 3.47.7 tương tự trong transcript trước switching, configs/format
đã restore. Root lib/test/adapters/.github trees không đổi so với 2a7e31b.
Evidence docs/progress/logs/kiosk-preview-integration/, review tương ứng.
11 regression mới có batch repeated/auto latch, snapshot cancel, acquire trễ,
ambiguous selection, hidden, Column unbounded-height và remount handoff.

## Giới hạn

Chỉ build fixture riêng, chưa build cả app kiosk riêng/hardware/light/control.
Caller phải điều phối camera_windows/UVC; compile coexistence không cấp shared
camera access. Device ID và preset cần kiểm tra trên thiết bị thật; hooks cần
completion/cancellation hữu hạn ở service. Physical GPU/USB/24–168h thiếu proof.
Product gate CHUA DAT. Không còn code task này. User cuối xác nhận chỉ tập trung
document_detect_windows; không tiếp tục xử lý repo thêm nhầm. Không thay saved
repository selection; thư mục repo thêm nhầm còn nguyên do lệnh xóa bị từ chối.
