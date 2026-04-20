import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

class DeviceSettingsHelper {
  static const MethodChannel _channel = MethodChannel(
    'fox.delivery/device_settings',
  );

  static Future<void> openNotificationSettings() async {
    if (GetPlatform.isAndroid && await _invoke('openNotificationSettings')) {
      return;
    }
    await openAppSettings();
  }

  static Future<void> openBatteryOptimizationSettings({
    bool requestDisableOptimization = true,
  }) async {
    if (GetPlatform.isAndroid) {
      final String method = requestDisableOptimization
          ? 'openBatteryOptimizationSettings'
          : 'openBatteryOptimizationListSettings';
      if (await _invoke(method)) {
        return;
      }
    }
    await openAppSettings();
  }

  static Future<void> openLocationPermissionSettings() async {
    if (GetPlatform.isAndroid && await _invoke('openAppDetailsSettings')) {
      return;
    }
    await openAppSettings();
  }

  static Future<bool> _invoke(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
