import 'package:fox_delivery_driver/interface/repository_interface.dart';

abstract class HtmlRepositoryInterface extends RepositoryInterface {
  Future<dynamic> getHtmlText(bool isPrivacyPolicy);
}