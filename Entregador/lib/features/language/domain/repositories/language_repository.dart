import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fox_delivery_driver/api/api_client.dart';
import 'package:fox_delivery_driver/features/language/domain/repositories/language_repository_interface.dart';
import 'package:fox_delivery_driver/util/app_constants.dart';

class LanguageRepository implements LanguageRepositoryInterface {
  final ApiClient apiClient;
  final SharedPreferences sharedPreferences;
  LanguageRepository({required this.apiClient, required this.sharedPreferences});

  @override
  void updateHeader(Locale locale) {
    apiClient.updateHeader(sharedPreferences.getString(AppConstants.token), _defaultLocale.languageCode);
  }

  @override
  Locale getLocaleFromSharedPref() {
    saveLanguage(_defaultLocale);
    return _defaultLocale;
  }

  @override
  void saveLanguage(Locale locale) async {
    sharedPreferences.setString(AppConstants.languageCode, _defaultLocale.languageCode);
    sharedPreferences.setString(AppConstants.countryCode, _defaultLocale.countryCode!);
  }

  @override
  void saveCacheLanguage(Locale locale) {
    sharedPreferences.setString(AppConstants.cacheLanguageCode, _defaultLocale.languageCode);
    sharedPreferences.setString(AppConstants.cacheCountryCode, _defaultLocale.countryCode!);
  }

  @override
  Locale getCacheLocaleFromSharedPref() {
    return _defaultLocale;
  }

  @override
  Future add(value) {
    throw UnimplementedError();
  }

  @override
  Future delete(int? id) {
    throw UnimplementedError();
  }

  @override
  Future get(int? id) {
    throw UnimplementedError();
  }

  @override
  Future getList() {
    throw UnimplementedError();
  }

  @override
  Future update(Map<String, dynamic> body) {
    throw UnimplementedError();
  }

  Locale get _defaultLocale => Locale(
    AppConstants.languages[0].languageCode!,
    AppConstants.languages[0].countryCode,
  );
}
