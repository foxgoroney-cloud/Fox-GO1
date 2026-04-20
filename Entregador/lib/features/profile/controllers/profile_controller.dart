import 'dart:async';
import 'package:fox_delivery_driver/common/models/response_model.dart';
import 'package:fox_delivery_driver/features/auth/controllers/auth_controller.dart';
import 'package:fox_delivery_driver/features/order/controllers/order_controller.dart';
import 'package:fox_delivery_driver/features/splash/controllers/splash_controller.dart';
import 'package:fox_delivery_driver/features/address/domain/models/record_location_body_model.dart';
import 'package:fox_delivery_driver/features/profile/domain/models/profile_model.dart';
import 'package:fox_delivery_driver/helper/route_helper.dart';
import 'package:fox_delivery_driver/common/widgets/custom_snackbar_widget.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fox_delivery_driver/features/profile/domain/services/profile_service_interface.dart';

class ProfileController extends GetxController implements GetxService {
  final ProfileServiceInterface profileServiceInterface;
  ProfileController({required this.profileServiceInterface});

  ProfileModel? _profileModel;
  ProfileModel? get profileModel => _profileModel;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  XFile? _pickedFile;
  XFile? get pickedFile => _pickedFile;

  RecordLocationBodyModel? _recordLocation;
  RecordLocationBodyModel? get recordLocationBody => _recordLocation;

  Timer? _timer;
  bool _isRecordingLocation = false;
  bool _isSyncingAvailability = false;

  bool _backgroundNotification = true;
  bool get backgroundNotification => _backgroundNotification;

  Future<void> getProfile() async {
    ProfileModel? profileModel = await profileServiceInterface.getProfileInfo();
    if (profileModel != null) {
      _profileModel = profileModel;
      if (_profileModel!.active == 1) {
        profileServiceInterface.checkPermission(() => startLocationRecord());
      } else {
        stopLocationRecord();
        Get.find<OrderController>().clearPendingIncomingOffer();
      }
    }
    update();
  }

  Future<bool> updateUserInfo(
    ProfileModel updateUserModel,
    String token,
  ) async {
    _isLoading = true;
    update();
    ResponseModel responseModel = await profileServiceInterface.updateProfile(
      updateUserModel,
      _pickedFile,
      token,
    );
    _isLoading = false;
    if (responseModel.isSuccess) {
      _profileModel = updateUserModel;
      Get.back();
      showCustomSnackBar(responseModel.message, isError: false);
    } else {
      showCustomSnackBar(responseModel.message, isError: true);
    }
    update();
    return responseModel.isSuccess;
  }

  void pickImage() async {
    _pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    update();
  }

  void initData() {
    _pickedFile = null;
  }

  Future<bool> updateActiveStatus() async {
    ResponseModel responseModel = await profileServiceInterface
        .updateActiveStatus();
    if (responseModel.isSuccess) {
      Get.back();
      _profileModel!.active = _profileModel!.active == 0 ? 1 : 0;
      showCustomSnackBar(responseModel.message, isError: false);
      if (_profileModel!.active == 1) {
        profileServiceInterface.checkPermission(() => startLocationRecord());
      } else {
        stopLocationRecord();
        Get.find<OrderController>().clearPendingIncomingOffer();
      }
    } else {
      showCustomSnackBar(responseModel.message, isError: true);
    }
    update();
    return responseModel.isSuccess;
  }

  Future deleteDriver() async {
    _isLoading = true;
    update();
    ResponseModel responseModel = await profileServiceInterface.deleteDriver();
    _isLoading = false;
    if (responseModel.isSuccess) {
      showCustomSnackBar(responseModel.message, isError: false);
      Get.find<AuthController>().clearSharedData();
      stopLocationRecord();
      Get.offAllNamed(RouteHelper.getSignInRoute());
    } else {
      Get.back();
      showCustomSnackBar(responseModel.message, isError: true);
    }
  }

  void startLocationRecord() {
    _timer?.cancel();
    recordLocation(syncAvailability: true);
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      recordLocation();
    });
  }

  void stopLocationRecord() {
    _timer?.cancel();
  }

  Future<void> recordLocation({bool syncAvailability = false}) async {
    if (_isRecordingLocation) {
      return;
    }

    _isRecordingLocation = true;
    try {
      final Position locationResult = await Geolocator.getCurrentPosition();
      String address = await profileServiceInterface.addressPlaceMark(
        locationResult,
      );

      _recordLocation = RecordLocationBodyModel(
        location: address,
        latitude: locationResult.latitude,
        longitude: locationResult.longitude,
      );

      await profileServiceInterface.recordLocation(_recordLocation!);

      if (Get.find<SplashController>().configModel!.webSocketStatus!) {
        try {
          await profileServiceInterface.recordWebSocketLocation(
            _recordLocation!,
          );
        } catch (_) {}
      }

      if (syncAvailability && (_profileModel?.active ?? 0) == 1) {
        await _syncAvailabilityAfterLocationPrime();
      }
    } catch (_) {
      // Keep the driver online even if a location sample fails momentarily.
    } finally {
      _isRecordingLocation = false;
      update();
    }
  }

  void setBackgroundNotificationActive(bool isActive) {
    _backgroundNotification = isActive;
    update();
  }

  Future<void> _syncAvailabilityAfterLocationPrime() async {
    if (_isSyncingAvailability || !Get.isRegistered<OrderController>()) {
      return;
    }

    _isSyncingAvailability = true;
    try {
      final OrderController orderController = Get.find<OrderController>();
      await orderController.getLatestOrders();
      await orderController.getRunningOrders(
        1,
        status: 'all',
        willUpdate: false,
      );
    } finally {
      _isSyncingAvailability = false;
    }
  }
}
