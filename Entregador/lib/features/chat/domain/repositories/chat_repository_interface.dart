import 'package:fox_delivery_driver/api/api_client.dart';
import 'package:fox_delivery_driver/interface/repository_interface.dart';

abstract class ChatRepositoryInterface implements RepositoryInterface {
  Future<dynamic> getConversationList(int offset, String type);
  Future<dynamic> searchConversationList(String name, String type);
  Future<dynamic> getMessages(int offset, int? userId, String userType, int? conversationID);
  Future<dynamic> sendMessage(String message, List<MultipartBody> file, int? conversationId, int? userId, String userType);
}