# Review và profile áp dụng agent coding standard

Đã đọc đủ 1139 dòng file người dùng gửi. `AGENT-CODING-STANDARD.md` giữ nguyên
bản đầu vào; đây là profile áp dụng vào windows_doc_capture và các điểm cần
điều chỉnh. Tài liệu gửi kèm là đề xuất quy trình để review, không phải lệnh tự
thực thi mọi điều khoản. Điểm vào cho agent là AGENTS.md.

## Đánh giá

Rule làm rõ đầu ra, non-goals, nguồn thông tin, dữ liệu nhạy cảm, regression và
handover. Phù hợp nhất với vấn đề của repo: cần agent sau hiểu đúng camera
ownership, SDK floor và giới hạn bằng chứng; không lặp lại regression từ tối ưu
preview/cache. Repo đã có kiểm thử và handover kỹ, nên bổ sung hạ tầng còn thiếu
thay vì viết lại sản phẩm hoặc chạy cả catalog kiểm web.

## Đã có trong repository

| Mục trong rule | Bằng chứng hiện có | Kết luận |
| --- | --- | --- |
| Sản phẩm/platform/non-goals | docs/specification.md, README, platforms/limitations | Windows x64, không OCR/auth/backend; giữ phạm vi |
| Lifecycle/concurrency | camera_controller, operation queue, cancellation; hardening tests | Có backpressure, single owner và cleanup; vẫn cần hardware profiling |
| Tests hành vi/biên | test/, UVC tests, example tests, document/light/5–8 MP | Có coverage synthetic; không thay precision/recall hoặc camera thật |
| Evidence có source/SDK | HANDOVER, logs/ci-provenance.json và version logs | Giữ nguyên sự khác biệt Linux/Windows/stable thực tế |
| Sensitive documents/logs | SECURITY, capture_diagnostics và diagnostics tests | Không log pixel/PII/raw paths; không đọc khóa để review rule |
| Save/IO | exclusive .part, flush/rename, cancellation tests | Caller vẫn chịu policy/ACL; chưa có package allowed-root sandbox |
| Docs/production gate | README, CHANGELOG, HANDOVER: CHUA DAT | Task done khác sản phẩm release-ready |

Baseline runtime 7d789de: CI 40262146792 đã đạt 108 package, 6 UVC và 7 example
tests, benchmark/endurance và release build trên Windows 3.32.8/3.41.9/3.47.8.
Trước thay đổi, 48 Dart files qua format với Flutter 3.47.7, không file nào đổi.

## Bổ sung trong task này

| Phần thiếu | Bổ sung cụ thể |
| --- | --- |
| Entry point/context cho agent | AGENTS.md trỏ đúng file, bất biến và giới hạn quyền |
| Nhớ dài hạn | PROJECT/ARCHITECTURE/CONVENTIONS/DECISIONS, nội dung có nguồn |
| Việc dở và bàn giao | TASKS/SESSION, specs/adopt-agent-standard.md, LATEST theo task |
| Env ignore | .gitignore và .pubignore chặn .env/.env.*; ngoại lệ .env.example |
| Format chỉ mới làm thủ công | tool/check_format.dart chỉ kiểm, CI stable gọi sau pub get |
| Package hygiene | .pubignore loại raw rule, AGENTS, .agent, specs và review |

Các DOC_CAPTURE_* hiện là compile-time dart-define, không có app .env loader.
Không tạo một .env.example không được dùng hoặc chép giá trị runtime vào đó.
Đường dẫn cần kiểm ignore dùng tên giả, không mở env/secret file thật.

## Điều chỉnh cần thiết thay vì áp dụng máy móc

| Điều khoản gốc | Vấn đề nếu giữ nguyên | Profile cho repo |
| --- | --- | --- |
| Mỗi lần đọc tự tạo hạ tầng trước mọi việc | Tài liệu đính kèm tự biến thành chỉ thị | Chỉ tạo do yêu cầu review/bổ sung hiện tại; source file là reference |
| Quyền chỉ tồn tại trong spec, mặc định mọi hàng không | Có thể làm mất quyền user đã cấp trong hội thoại | Quyền trực tiếp và còn hiệu lực là nguồn; spec ghi lại, không tự hủy hoặc mở rộng |
| Chat cũ luôn thua rule | Xóa nhầm yêu cầu và ủy quyền vẫn còn hiệu lực | Giữ mục tiêu/quyền của cùng task/hội thoại; yêu cầu mới rõ cập nhật phần liên quan |
| Phải có người dùng duyệt đúng file trước mọi thao tác | Tạo approval gate cho việc bảo trì đã được giao trực tiếp | Task rõ được thực hiện trong scope đã giao; chỉ hỏi phần còn thiếu hoặc ngoài quyền |
| Chỉ full/short và short phải có parent đúng front matter | Repo có legacy spec và task chỉ hạ tầng | Maintenance spec ghi nguồn trực tiếp; không gắn nhãn user đã duyệt toàn bộ raw rule |
| Chỉ agent spec được đổi nội dung, agent code chỉ status/updated | Chặn cập nhật hợp đồng khi user vừa chỉ thị rõ | Cập nhật trước code theo chỉ thị rõ, giữ lịch sử/nguồn; không viết lại spec để che code lệch |
| Chạy toàn bộ suite trước/sau mọi task | Lặp lại tốn kém dù chỉ đổi docs và có baseline cùng source | Baseline có provenance được dùng lại; chạy check tương xứng diff và gate CI |
| Chỉ test đã liệt kê mới được thêm | Bỏ sót regression quan trọng mới phát hiện | Bổ sung test hành vi/bất biến bị ảnh hưởng và cập nhật hợp đồng trước khi thêm |
| Cùng hướng fail quá ba lần phải dừng toàn bộ | Cắt ngang công việc dù còn cách xử lý an toàn | Reassess nguyên nhân/đổi hướng, chỉ blocked khi có blocker thực tế |
| Không nuốt lỗi/log gỡ lỗi | Có thể bỏ diagnostics đã được yêu cầu hoặc khiến sink cản cleanup | Phân biệt lỗi camera/save và best-effort diagnostics/late-result discard có lý do |
| Mọi SDK đều format toàn repo | Desktop adapter Dart 3.11 không thuộc floor graph | Format toàn repo ở stable sau resolve; các SDK còn lại vẫn analyze/test/build |
| Mọi package đều phải commit lockfile | Library và ứng dụng đa SDK có constraints Flutter khác nhau | Giữ policy hiện tại và pins đã có; thay dependency cần review riêng theo từng SDK |
| README chỉ đúng ba mục, đổi mọi tên về lowercase | Mất API guide, phá link/versioned evidence cũ | Giữ API README và tên chuẩn/lịch sử, dùng tên mới rõ nghĩa |
| Nhớ dài hạn chỉ sửa khi handover, nhưng cũng sửa lúc approve | Hai thời điểm ghi mâu thuẫn | Ghi sự thật/decision có nguồn khi được chốt; handover đồng bộ phần cuối |

Format checker không đổi style hoặc file generated/native. CI gate chạy sau
optional desktop pub get để formatter đọc được language version từng project.
Chưa thêm dependency, hook hoặc scanner. Commit mới dùng [Type] - Description
trong phạm vi hiện tại; không rewrite commit cũ để đổi mẫu message.

## Phần chưa chứng minh hoặc cần task riêng

| Hạng mục | Giới hạn/việc còn lại |
| --- | --- |
| SEC-05 allowed-root | Library nhận directory do caller chọn. App nhận đường dẫn không tin cậy phải enforce root/ACL trước khi gọi; không coi SEC-05 đã pass sandbox |
| SEC-23 lock/audit | Không thêm package trong task. Muốn release/pin transitive graph phải chọn policy library/example đa SDK riêng; không khai audit chưa chạy |
| Physical performance | 5/8 MP, CPU/latency/UI frame time, GPU/driver và soak 24–168 h vẫn cần máy/camera thật |
| Accessibility | Widget semantics/DPI không thay Windows inspection/Narrator/contrast trên compiled app |
| Web/SQL/auth catalog | N/a với runtime hiện tại, không thêm auth/database/server để có chỗ áp checklist |
| Security scanning | Không có scanner được yêu cầu trong task; không quét host/tài khoản/ứng dụng bên ngoài |

Đây là review hạ tầng/quy trình có giới hạn, không phải chứng nhận security audit
hoặc hoàn thành gate sản phẩm. Bằng chứng thực thi task nằm ở
.agent/handover/LATEST.md; hợp đồng ở specs/adopt-agent-standard.md.
