# Bối cảnh phiên

- Rule review đã commit b66ce7f, chưa push; original raw file giữ nguyên.
- Local standard checks: formatter 49 files pass, dirty/missing fixture fail đúng,
  không ghi lại file; env patterns pass; analyze root pass.
- User bổ sung log 5 và yêu cầu preview mượt hơn; task specs/smooth-bitmap-preview.md.
- Log: 433 events/~420 s, 7 sessions, 6/6 captures success, không library/GPU error
  trong file. Native ~30 FPS, analysis/bitmap 5 FPS; veryHigh thực tế 1280×720.
- Cần giữ stream identity/dispose/cache fixes trước, không tăng queue hoặc dùng texture lại.
