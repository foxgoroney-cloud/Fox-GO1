import 'package:flutter_test/flutter_test.dart';
import 'package:fox_delivery_driver/util/app_constants.dart';

void main() {
  test('uses Fox Delivery branding constants', () {
    expect(AppConstants.appName, 'Fox Delivery');
    expect(AppConstants.baseUrl, 'https://www.foxgodelivery.com.br');
  });
}
