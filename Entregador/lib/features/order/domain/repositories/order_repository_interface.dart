import 'package:fox_delivery_driver/api/api_client.dart';
import 'package:fox_delivery_driver/features/order/domain/models/ignore_model.dart';
import 'package:fox_delivery_driver/features/order/domain/models/order_count_model.dart';
import 'package:fox_delivery_driver/features/order/domain/models/order_model.dart';
import 'package:fox_delivery_driver/features/order/domain/models/parcel_cancellation_reasons_model.dart';
import 'package:fox_delivery_driver/features/order/domain/models/update_status_body_model.dart';
import 'package:fox_delivery_driver/interface/repository_interface.dart';

abstract class OrderRepositoryInterface implements RepositoryInterface {
  Future<dynamic> getCancelReasons();
  Future<dynamic> getCompletedOrderList(
    int offset, {
    String orderStatus = 'all',
  });
  Future<dynamic> getCurrentOrders(int offset, {String orderStatus = 'all'});
  Future<dynamic> getLatestOrders();
  Future<dynamic> updateOrderStatus(
    UpdateStatusBodyModel updateStatusBody,
    List<MultipartBody> proofAttachment,
  );
  Future<dynamic> getOrderDetails(int? orderID);
  Future<dynamic> acceptOrder(int? orderID);
  Future<dynamic> rejectOrder(int? orderID, {required bool expired});
  List<IgnoreModel> getIgnoreList();
  void setIgnoreList(List<IgnoreModel> ignoreList);
  Future<ParcelCancellationReasonsModel?> getParcelCancellationReasons({
    required bool isBeforePickup,
  });
  Future<bool> addParcelReturnDate({
    required int orderId,
    required String returnDate,
  });
  Future<bool> submitParcelReturn({
    required int orderId,
    required String orderStatus,
    required int returnOtp,
  });
  Future<List<OrderCountModel>?> getOrderCount(String type);
  Map<String, String> getDeliveryOperationStages();
  Future<void> setDeliveryOperationStage(int orderId, String stageKey);
  Future<void> clearDeliveryOperationStage(int orderId);
  double getDeliveryGeofenceRadius();
  Future<void> setDeliveryGeofenceRadius(double radiusInMeters);
  Future<void> persistPendingIncomingOffer(OrderModel? orderModel);
  OrderModel? getPersistedPendingIncomingOffer();
}
