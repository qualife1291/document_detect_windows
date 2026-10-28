# Tích hợp vào kiosk GetX đang dùng CameraPlatform

Áp dụng cho `camera_preview_widget.dart` và ATNProofIDController/ATNContainerCaptureProofID
bạn cung cấp, cùng ATNUploadProofController gửi bổ sung. Widget thay thế trong example:
[CameraPreviewWidget](../../example/lib/integration/camera_preview_widget.dart).
Không cần sửa nghiệp vụ review ảnh, repository hoặc AI để nhận JPEG mới.
Chưa có toàn bộ project kiosk/service phần cứng nên đây là bản tích hợp có hook,
không phải tuyên bố đã build thành công ứng dụng kiosk của bạn.

## 1. Thêm dependency, chép widget

Flutter Windows x64 >=3.32.8/Dart >=3.8.1, Visual Studio Desktop C++ như README.
Ví dụ hai repository nằm cạnh nhau:

```yaml
dependencies:
  windows_doc_capture:
    path: ../document_detect_windows
  windows_doc_capture_uvc:
    path: ../document_detect_windows/adapters/windows_doc_capture_uvc
```

Chép `example/lib/integration/camera_preview_widget.dart` vào vị trí widget camera
của kiosk. File độc lập chỉ import Flutter và hai package trên; không cần thêm
GetX vào package. Thay file/barrel export hiện có, không import song song hai
CameraPreviewController khác nhau cùng tên. Giữ tên `CameraPreviewWidget`/`CameraPreviewController` nên
`controller.cameraPreviewController.capture()` và `onCaptured` vẫn dùng được.
Có hai chế độ theo từng chỗ dùng:

| Nơi dùng | captureMode | Sau callback |
| --- | --- | --- |
| ATNProofIDController / một ID rồi review | DocumentCameraCaptureMode.single | Camera/đèn dừng trước callback |
| ATNUploadProofController / nhiều chứng từ | DocumentCameraCaptureMode.batch | Giữ cùng camera để chụp tiếp |

Widget chung mặc định batch để giữ hành vi preview liên tục của code cũ.
Wrapper bước ID ở dưới chọn single rõ ràng; các nơi dùng khác cần rà theo flow.
Giữ một instance CameraPreviewController trong ATNProofIDController như hiện tại.
Không tạo lại controller hoặc WindowsDocCapture trong build()/Obx().

Bỏ import camera_platform_interface khỏi widget này để tránh trùng
ResolutionPreset. Không cần gỡ camera_windows/camera khỏi toàn project nếu tính
năng khác vẫn dùng chúng. Chỉ thay camera giấy tờ; camera cũ phải đóng hoàn toàn
trước khi UVC mở cùng thiết bị. Hai plugin cùng được cài không có nghĩa được mở
cùng camera đồng thời. Widget này Windows x64 only; mobile dev giữ implementation
cũ riêng, không trỏ mobile vào UVC.

## 2. Nối camera và vòng đời đèn/phần cứng

Đặt các hàm dưới đây trong file wrapper kiosk, với các import service hiện tại.
Tên service lấy từ code đã gửi; cần kiểm tra hợp đồng acquire/release thực tế.

```dart
import 'dart:async';
import 'package:windows_doc_capture/windows_doc_capture.dart';
// import widget thay thế và các service của kiosk.

CameraDevice selectProofCamera(List<CameraDevice> devices) {
  final configured = KioskConfigService.camCameraScanId.trim();
  // ID từ camera_windows có thể KHÁC ID của UVC: cấu hình lại nếu không khớp.
  final byId = devices.where((d) => d.id == configured).toList();
  if (configured.isNotEmpty && byId.length == 1) return byId.single;
  final byName = devices.where((d) => d.name == configured).toList();
  if (configured.isNotEmpty && byName.length == 1) return byName.single;
  throw StateError('Document camera configuration is missing or ambiguous');
}

Future<CameraHardwareRelease> acquireProofHardware() async {
  final release = KioskHardwareService.instance.acquire();
  try {
    await Future<void>.sync(LightControlService.turnOn);
  } catch (error, stack) {
    try {
      await Future<void>.sync(LightControlService.turnOff);
    } catch (_) {
      // Giữ lỗi bật đèn ban đầu; vẫn nhả lease bên dưới.
    }
    release();
    Error.throwWithStackTrace(error, stack);
  }
  return () async {
    try {
      await Future<void>.sync(LightControlService.turnOff);
    } finally {
      release();
    }
  };
}
```

`selectProofCamera` nhận danh sách UVC mới ở mỗi lần mở. Không tự chọn camera đầu
tiên khi cấu hình sai: kiosk có thể có cả camera khuôn mặt và camera giấy tờ.
Nếu dùng màn hình settings để chọn, lưu `device.id` của UVC; không debugPrint
ID/tên thiết bị hoặc giả định tên model là duy nhất. Chỉ enumerate khi camera dừng.
Hook acquire phải tự rollback nếu lỗi trước khi trả về hàm release. acquire()
trong service hiện tại chưa được kiểm tra: nó không tự chứng minh có mutex chung
cho camera_windows/UVC; app vẫn phải điều phối các tính năng camera.

Code cũ gọi `CameraDeviceControls.apply(selectedCamera.name, settings)`. Chưa có
source service này nên **chưa gọi lại tự động**: ID/backend có thể khác và service
có thể mở một camera khác. Sau khi xác nhận nó hỗ trợ UVC mà không mở camera mới,
có thể nối `configureCamera: (device) => ...`. Hook được await trước khi widget
bật auto capture. Nếu kiosk cần 5/8 MP, thử preset veryHigh và kiểm tra độ phân giải thật trong
log; mặc định high ưu tiên cân bằng tải. Snapshot lấy đúng chế độ camera thương lượng; preset không
bảo đảm có đủ MP nếu phần cứng chỉ hỗ trợ 1280x720.

## 3. Thay ATNContainerPreviewCameraProofID

Ví dụ wrapper giữ nguyên tham số controller mà ATNContainerCaptureProofID dùng:

```dart
class ATNContainerPreviewCameraProofID extends StatelessWidget {
  const ATNContainerPreviewCameraProofID({
    super.key,
    required this.cameraPreviewController,
    this.onDocumentStateChanged,
    this.captureMode = DocumentCameraCaptureMode.single,
  });

  final CameraPreviewController cameraPreviewController;
  final ValueChanged<DocumentPreviewState>? onDocumentStateChanged;
  final DocumentCameraCaptureMode captureMode;

  Future<void> _focusAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Widget hiển thị lỗi camera an toàn. Không log raw error/device/path.
    }
  }

  @override
  Widget build(BuildContext context) => FocusDetector(
    // Dùng các callback FocusDetector đã có trong project.
    onFocusGained: () => unawaited(_focusAction(cameraPreviewController.resume)),
    onFocusLost: () => unawaited(_focusAction(cameraPreviewController.stop)),
    child: SizedBox(
      height: 400,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CameraPreviewWidget(
          controller: cameraPreviewController,
          selectCamera: selectProofCamera,
          acquireHardware: acquireProofHardware,
          captureMode: captureMode,
          enableAutoCapture: false, // bật true riêng ở nơi muốn tự chụp.
          preset: ResolutionPreset.high,
          cornerRadius: 6,
          warningColor: Colors.white,
          validColor: Colors.greenAccent,
          onDocumentStateChanged: onDocumentStateChanged,
        ),
      ),
    ),
  );
}
```

Wrapper cần import Flutter/material, focus_detector, widget mới, root package và
service/hàm ở mục 2. Trong flow đã gửi, `onInit()` vẫn giữ:

```dart
cameraPreviewController.onCaptured = onPhotoCaptured;
```

Không truyền thêm widget.onCaptured gọi cùng `onPhotoCaptured`: mẫu mới chỉ dùng
một callback, ưu tiên widget.onCaptured nếu có. Ở chế độ single, callback nhận
cropped JPEG sau khi camera dừng VÀ hook release hoàn tất. Vì vậy code hiện tại có thể gán
proofID, gọi reviewIdPhoto và mở dialog ngay. Manual và auto cùng đi vào callback
này; `capture()` hoàn tất sau khi callback đồng bộ chạy xong, phù hợp AI kiểm tra
proofID ngay sau await. Nó không đợi AWS/review dialog của app hoàn tất.

Tùy chọn enum cho GetX trong ATNProofIDController:

```dart
final documentState = DocumentPreviewState.idle.obs;
// Tại chỗ tạo ATNContainerPreviewCameraProofID:
// onDocumentStateChanged: (state) => controller.documentState.value = state,
```

Các enum gồm processing, noDocument, outOfFrame, tooDark, tooBright, blurry,
tilted, clear, capturing, cooldown, error, idle. Chỉ dùng enum đổi trạng thái cho
UI/AI gợi ý; không gọi AWS hoặc rebuild cả trang ở từng frame. Bốn góc tự theo
previewStatus trong package. `clear` không bảo đảm OCR đọc được mọi chữ nhỏ.

## 4. ATNUploadProofController: chụp nhiều ảnh không phải mở lại camera

Ở nơi tạo wrapper của màn upload, truyền thêm:

```dart
ATNContainerPreviewCameraProofID(
  cameraPreviewController: controller.cameraPreviewController,
  captureMode: DocumentCameraCaptureMode.batch,
)
```

Callback đang có vẫn giữ cách thêm Uint8List vào filesEligibilityProof. Nên thêm
_closed guard và giới hạn số ảnh/tổng bytes theo chính sách kiosk để danh sách
ảnh trong RAM không tăng vô hạn:

```dart
bool _closed = false;
// Trong onInit:
cameraPreviewController.onCaptured = (bytes) {
  if (_closed) return;
  filesEligibilityProof.add(bytes);
};
```

Trong batch, callback chạy khi camera còn hoạt động: chỉ thêm ảnh/giao việc có
giới hạn; không mở camera thứ hai từ callback. Nút chụp và AI take_photo tiếp tục
await capture() như cũ; sau await, số ảnh đã tăng. Camera chỉ start một lần cho
nhiều ảnh; không stop/start mỗi tấm, giảm chi phí cho máy yếu. Tự chụp nếu bật vẫn
cần bỏ giấy khỏi khung và qua cooldown; không reset latch khi Obx rebuild.

Trước showDetailProofs/showSampleProof, confirmation skip_documents, upload hoặc
navigation: await cameraPreviewController.stop(). Nếu chỉ đóng dialog rồi quay
lại chụp, resume sau khi dialog đóng, route vẫn đúng và !_closed. Không dùng
shutdown cho dialog tạm thời; shutdown là kết thúc instance widget.

Ở onTapContinue của ATNUploadProofController, stop trước _onUploadProof để camera
không thêm ảnh vào danh sách trong khi bạn snapshot/base64/upload. Nếu upload
thất bại và vẫn ở route uploadProof thì resume. Base64 nhiều ảnh vẫn có thể
làm nghẽn UI isolate: giới hạn ảnh, đo thực tế rồi chuyển encode sang worker nếu
cần; không tự đổi format request khi chưa đổi hợp đồng API. Trước Get.toNamed kiểm tra lại
_closed/currentRoute/command.canApply như các guard hiện tại; không mở camera
khác nếu stop lỗi. Nhánh back/skip_documents cũng await stop trước navigation.
Trong AI take_photo dùng try/catch rồi kiểm tra count như code hiện tại.

onClose: _closed = true, onCaptured = null, shutdown best effort và hủy AI
registration. Chỉ giải phóng danh sách ảnh khi app không còn cần bytes (ví dụ
upload thành công/thoát enrollment); không xóa bừa MediaModel trên server.
Widget/package không tự thêm file hoặc giữ lịch sử ảnh hộ app.

## 5. Điều chỉnh navigation và lỗi thao tác trong controller

Giữ nguyên onPhotoCaptured, _analyzePhoto, review/extract và các revision guard.
Chụp không tạo file: không có takePicture/XFile/readAsBytes/processScanImage hay
saveDirectory trong luồng mới. Các request review/upload của app vẫn do app làm.

Thêm catch an toàn khi người dùng/AI bấm lúc camera chưa sẵn sàng hoặc đang chụp:

```dart
Future<void> onCaptureOrReview() async {
  if (_closed || reviewOpen.value) return;
  if (proofID.value != null) {
    await onReviewProofId();
    return;
  }
  try {
    await cameraPreviewController.capture();
  } catch (_) {
    if (!_closed) FlutterToast.showToastError(message: 'starting_camera'.tr);
  }
}
```

Nhánh AI `take_photo` cũng bọc await capture() bằng try/catch và gọi
`data.fail('camera_capture_failed')` khi lỗi; không đánh dấu thành công trước
callback. Manual thiếu quad sẽ không trả ảnh; kiểm tra proofID như code hiện tại.

Ở mọi đường rời step hoặc bàn giao cho camera khác, **await stop trước navigation**:

```dart
await cameraPreviewController.stop();
if (_closed || Get.currentRoute != AirTalkEnrollmentRoutes.proofID) return;
// Sau đó mới Get.back() / Get.toNamed(...) theo nhánh hiện tại.
```

Áp dụng vào AI `back`, route verifyInfo ở `_continueWithProof` và route verifyInfo
ở `onProvideIdLater`. Nếu stop lỗi, không mở camera khác; hiển thị lỗi để operator
xử lý. FocusDetector/dispose là fallback, không thay được awaited handoff.

Khi mở dialog "để sau", dừng camera trước khi show dialog để auto capture không
mở thêm dialog review ở phía dưới. Nếu người dùng hủy và vẫn ở step này,
proofID == null, resume sau khi dialog đóng và widget vẫn mounted. Nếu xác nhận
để sau, giữ camera dừng và điều hướng. Kiểm tra lại _closed/currentRoute sau await.

`retakePhoto()` trong code đã gửi gán proofID = null làm Obx mount preview mới;
không gọi resume ngay trước khi widget mới mount. Widget tự khởi động và await
cleanup của instance cũ dùng chung controller. Nếu host giữ preview bằng Offstage
thay vì unmount, cần active=false/await stop khi ẩn, active=true/resume khi hiện.

Bổ sung trong onClose (callback GetX không await được):

```dart
cameraPreviewController.onCaptured = null;
unawaited(cameraPreviewController.shutdown().catchError((Object _) {
  // Fallback cleanup; navigation bình thường đã await stop ở trên.
}));
```

Giữ nguyên `_closed`, revision increment và hủy AI registration hiện tại.
Widget còn tự stop khi app hidden/paused/detached. Core widget không stop chỉ vì inactive. Wrapper FocusDetector ở trên vẫn có
thể phát onFocusLost khi mở dialog/đổi focus (như code cũ); nó sẽ gọi stop.
Nếu cần phân biệt đúng visibility với focus, nối active/RouteAware từ navigator
của host. Chỉ TickerMode/Offstage không đủ nhả native camera.
Quay lại từ background cần resume qua route/operator, không tự giành lại camera.

## 6. Bỏ geometry cũ, giới hạn decode ảnh kết quả

- Bỏ `zoom`, DocumentCameraZoom.factor, cropCamLeft/Top/Width/Height,
  isCamScanCropped, processScanImage và Transform.flip khỏi preview giấy tờ mới.
  Widget mới không có tham số zoom: sửa các call site đang truyền zoom.
- Không bọc thêm crop/zoom/mirror bên ngoài preview mới. Quad và crop cùng dùng
  frame gốc; mirror bên ngoài sẽ làm chữ bị đảo. Mặc định BoxFit.contain để giữ
  toàn bộ khung và geometry đúng. Máy có khay crop cố định cần kiểm tra lại bố trí.
- Giữ Image.memory hiện tại nếu muốn UI cũ, nhưng nên giới hạn cacheWidth/cacheHeight
  theo kích thước hiển thị/DPI và không phóng to ảnh nhỏ. Có mẫu
  [CaptureResultImage](../../example/lib/capture_result_image.dart) decode cap1280,
  scaleDown và evict provider riêng. Không clear image cache toàn kiosk.
- Không cần export pair hoặc file_selector trong app kiosk nếu không xuất ảnh.
  Root/UVC là hai dependency cần thiết; camera_desktop không đáp ứng no-temp-file.

## Kiểm tra trên kiosk

Build Windows profile/release với DOC_CAPTURE_LOGS=true. Test camera scan được
chọn đúng khi cắm cả camera face; manual/auto chỉ gọi onPhotoCaptured một lần;
review ID có camera/đèn đã dừng; batch chụp được nhiều tấm mà chỉ mở camera một lần; chụp lại nhiều vòng; Back/skip/AI navigation; USB rút;
ẩn tab/route, minimize/restore và thoát trong lúc start/capture/hardware hook đang
chờ. Kiểm tra ổ đĩa không xuất hiện ảnh mới. Test preset và profile thấp hơn trên
máy yếu. Chưa có chứng nhận camera/GPU/USB/24–168h từ widget tests.
