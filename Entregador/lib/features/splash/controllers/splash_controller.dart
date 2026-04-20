import 'package:fox_delivery_driver/common/models/config_model.dart';
import 'package:get/get.dart';
import 'package:fox_delivery_driver/features/order/controllers/order_controller.dart';
import 'package:fox_delivery_driver/features/splash/domain/services/splash_service_interface.dart';

class SplashController extends GetxController implements GetxService {
  final SplashServiceInterface splashServiceInterface;
  SplashController({required this.splashServiceInterface});

  ConfigModel? _configModel;
  ConfigModel? get configModel => _configModel;

  bool _firstTimeConnectionCheck = true;
  bool get firstTimeConnectionCheck => _firstTimeConnectionCheck;

  int? _storeCategoryID;
  int? get storeCategoryID => _storeCategoryID;

  String? _storeType;
  String? get storeType => _storeType;

  Map<String, dynamic>? _data = {};

  DateTime get currentTime => DateTime.now();

  Module getModuleConfig(String? moduleType) {
    Module module = Module.fromJson(_data!['module_config'][moduleType]);
    moduleType == 'food' ? module.newVariation = true : module.newVariation = false;
    return module;
  }

  Future<bool> getConfigData() async {
    Response response = await splashServiceInterface.getConfigData();
    bool isSuccess = false;
    if(response.statusCode == 200) {
      _data = response.body;
      _configModel = ConfigModel.fromJson(response.body);
      if (Get.isRegistered<OrderController>()) {
        Get.find<OrderController>().syncDeliveryGeofenceRadiusFromConfig(_configModel, shouldUpdate: false);
      }
      isSuccess = true;
    }else {
      isSuccess = false;
    }
    update();
    return isSuccess;
  }

  Module getModule(String? moduleType) => Module.fromJson(_data!['module_config'][moduleType]);

  Future<bool> initSharedData() {
    return splashServiceInterface.initSharedData();
  }

  Future<bool> removeSharedData() {
    return splashServiceInterface.removeSharedData();
  }

  void setFirstTimeConnectionCheck(bool isChecked) {
    _firstTimeConnectionCheck = isChecked;
  }

}
