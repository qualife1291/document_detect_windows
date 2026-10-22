# Nielsen review — 2026-10-22

Đối tượng bắt buộc: example Windows đã build, có preview/warning/result.
Hiện chỉ xem source và widget-test render trên Linux, chưa có bản Windows hoặc
accessibility inspection. Các dòng dưới **không** xác nhận heuristic đã đạt.

| # | Heuristic | Kết quả | Màn/chứng cứ hiện có và còn thiếu |
| --- | --- | --- | --- |
| 1 | Visibility of system status | Không đạt | Source preview có camera status, warning, analysis metrics; chưa xem bản Windows, thiếu preview latency |
| 2 | Match system / real world | Không đạt | Widget test có warning tiếng Việt; chưa review kiosk Windows |
| 3 | User control and freedom | Không đạt | Widget test manual/result/Chụp lại/Esc, source toggle auto; chưa review Windows keyboard |
| 4 | Consistency and standards | Không đạt | Source preview/result dùng icon, text và Material controls; chưa xem Windows |
| 5 | Error prevention | Không đạt | Unit test stable/motion/feedback; chưa thực nghiệm đặt/bỏ giấy trên Windows |
| 6 | Recognition rather than recall | Không đạt | Source legend và warning text; chưa review màn thật |
| 7 | Flexibility and efficiency | Không đạt | Source manual/auto/device choice; chưa review với camera Windows |
| 8 | Aesthetic and minimalist | Không đạt | Widget test preview và result; chưa xem trên kiosk/4K |
| 9 | Recover from errors | Không đạt | Source permission/USB/IO text và retry; chưa thử Windows group policy/unplug |
| 10 | Help and documentation | Không đạt | Có footer và README/limitations; chưa review bản build Windows cùng operator |

Sau khi có bản Windows, review từng màn và lưu log có ngày, SDK, thiết bị. Chỉ
đổi từng dòng thành Đạt khi đã quan sát đúng đối tượng yêu cầu.
