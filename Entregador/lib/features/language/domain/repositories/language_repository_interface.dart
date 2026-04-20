import 'package:flutter/material.dart';
import 'package:fox_delivery_driver/interface/repository_interface.dart';

abstract class LanguageRepositoryInterface extends RepositoryInterface {
  void updateHeader(Locale locale);
  Locale getLocaleFromSharedPref();
  void saveLanguage(Locale locale);
  void saveCacheLanguage(Locale locale);
  Locale getCacheLocaleFromSharedPref();
}