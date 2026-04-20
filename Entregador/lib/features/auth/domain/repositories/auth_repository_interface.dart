import 'package:fox_delivery_driver/api/api_client.dart';
import 'package:fox_delivery_driver/features/auth/domain/models/delivery_man_body_model.dart';
import 'package:fox_delivery_driver/interface/repository_interface.dart';

abstract class AuthRepositoryInterface implements RepositoryInterface {
  Future<dynamic> login(String phone, String password);
  Future<dynamic> updateToken();
  Future<bool> saveUserToken(String token, String zoneTopic, String vehicleWiseTopic);
  String getUserToken();
  bool isLoggedIn();
  Future<bool> clearSharedData();
  Future<void> saveUserNumberAndPassword(String number, String password, String countryDialCode, String countryCode);
  String getUserNumber();
  String getUserCountryDialCode();
  String getUserCountryCode();
  String getUserPassword();
  bool isNotificationActive();
  void setNotificationActive(bool isActive);
  Future<bool> clearUserNumberAndPassword();
  Future<dynamic> registerDeliveryMan(DeliveryManBodyModel deliveryManBody, List<MultipartBody> multiParts);
}