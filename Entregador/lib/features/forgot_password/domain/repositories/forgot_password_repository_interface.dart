import 'package:fox_delivery_driver/common/models/response_model.dart';
import 'package:fox_delivery_driver/features/profile/domain/models/profile_model.dart';
import 'package:fox_delivery_driver/interface/repository_interface.dart';

abstract class ForgotPasswordRepositoryInterface implements RepositoryInterface {
  Future<dynamic> changePassword(ProfileModel userInfoModel, String password);
  Future<dynamic> forgetPassword(String? phone);
  Future<dynamic> verifyToken(String? phone, String token);
  Future<dynamic> resetPassword(String? resetToken, String phone, String password, String confirmPassword);
  Future<ResponseModel> verifyFirebaseOtp({required String phoneNumber, required String session, required String otp});
}