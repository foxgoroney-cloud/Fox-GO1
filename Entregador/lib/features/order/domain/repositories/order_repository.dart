import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fox_delivery_driver/api/api_client.dart';
import 'package:fox_delivery_driver/common/models/response_model.dart';
import 'package:fox_delivery_driver/features/order/domain/models/ignore_model.dart';
import 'package:fox_delivery_driver/features/order/domain/models/order_cancellation_body.dart';
import 'package:fox_delivery_driver/features/order/domain/models/order_details_model.dart';
import 'package:fox_delivery_driver/features/order/domain/models/order_model.dart';
import 'package:fox_delivery_driver/features/order/domain/models/parcel_cancellation_reasons_model.dart';
import 'package:fox_delivery_driver/features/order/domain/models/update_status_body_model.dart';
import 'package:fox_delivery_driver/features/order/domain/repositories/order_repository_interface.dart';
import 'package:fox_delivery_driver/util/app_constants.dart';

import '../models/order_count_model.dart';

class OrderRepository implements OrderRepositoryInterface {
  final ApiClient apiClient;
  final SharedPreferences sharedPreferences;
  OrderRepository({required this.apiClient, required this.sharedPreferences});

  @override
  Future<List<CancellationData>?> getCancelReasons() async {
    List<CancellationData>? orderCancelReasons;
    Response response = await apiClient.getData(
      '${AppConstants.orderCancellationUri}?offset=1&limit=30&type=deliveryman',
    );
    if (response.statusCode == 200) {
      OrderCancellationBody orderCancellationBody =
          OrderCancellationBody.fromJson(response.body);
      orderCancelReasons = [];
      for (var element in orderCancellationBody.reasons!) {
        orderCancelReasons.add(element);
      }
    }
    return orderCancelReasons;
  }

  @override
  Future<Response> get(int? id) async {
    Response response = await apiClient.getData(
      '${AppConstants.currentOrderUri}${_getUserToken()}&order_id=$id',
      handleError: false,
    );
    return response;
  }

  @override
  Future<PaginatedOrderModel?> getCompletedOrderList(
    int offset, {
    String orderStatus = 'all',
  }) async {
    PaginatedOrderModel? paginatedOrderModel;
    Response response = await apiClient.getData(
      '${AppConstants.allOrdersUri}?token=${_getUserToken()}&offset=$offset&limit=10&order_status=$orderStatus',
      handleError: false,
    );
    if (response.statusCode == 200) {
      paginatedOrderModel = PaginatedOrderModel.fromJson(response.body);
    }
    return paginatedOrderModel;
  }

  // @override
  // Future<PaginatedOrderModel?> getCompletedOrderList(int offset) async {
  //   PaginatedOrderModel? paginatedOrderModel;
  //   Response response = await apiClient.getData('${AppConstants.allOrdersUri}?token=${_getUserToken()}&offset=$offset&limit=10&');
  //   if (response.statusCode == 200) {
  //     paginatedOrderModel = PaginatedOrderModel.fromJson(response.body);
  //   }
  //   return paginatedOrderModel;
  // }

  @override
  Future<List<OrderModel>?> getLatestOrders() async {
    List<OrderModel>? latestOrderList;
    Response response = await apiClient.getData(
      AppConstants.latestOrdersUri + _getUserToken(),
      handleError: false,
    );
    if (response.statusCode == 200) {
      latestOrderList = [];
      response.body.forEach(
        (order) => latestOrderList!.add(OrderModel.fromJson(order)),
      );
    }
    return latestOrderList;
  }

  @override
  Future<ResponseModel> updateOrderStatus(
    UpdateStatusBodyModel updateStatusBody,
    List<MultipartBody> proofAttachment,
  ) async {
    updateStatusBody.token = _getUserToken();
    ResponseModel responseModel;

    Map<String, String> data;

    if (updateStatusBody.isParcel ?? false) {
      data = {
        '_method': 'put',
        'token': updateStatusBody.token!,
        'order_id': updateStatusBody.orderId.toString(),
        'status': updateStatusBody.status.toString(),
        'otp': updateStatusBody.otp.toString(),
        'reason': updateStatusBody.reasons.toString(),
        'note': updateStatusBody.comment ?? '',
      };
    } else {
      data = {
        '_method': 'put',
        'token': updateStatusBody.token!,
        'order_id': updateStatusBody.orderId.toString(),
        'status': updateStatusBody.status.toString(),
        'otp': updateStatusBody.otp.toString(),
        'reason': updateStatusBody.reason ?? '',
      };
    }

    Response response = await apiClient.postMultipartData(
      AppConstants.updateOrderStatusUri,
      data,
      proofAttachment,
      handleError: false,
    );
    if (response.statusCode == 200) {
      responseModel = ResponseModel(true, response.body['message']);
    } else {
      responseModel = ResponseModel(false, response.statusText);
    }
    return responseModel;
  }

  @override
  Future<List<OrderDetailsModel>?> getOrderDetails(int? orderID) async {
    List<OrderDetailsModel>? orderDetailsModel;
    Response response = await apiClient.getData(
      '${AppConstants.orderDetailsUri}${_getUserToken()}&order_id=$orderID',
    );
    if (response.statusCode == 200) {
      orderDetailsModel = [];
      response.body.forEach(
        (orderDetails) =>
            orderDetailsModel!.add(OrderDetailsModel.fromJson(orderDetails)),
      );
    }
    return orderDetailsModel;
  }

  @override
  Future<ResponseModel> acceptOrder(int? orderID) async {
    ResponseModel responseModel;
    final Position locationResult = await Geolocator.getCurrentPosition();
    Response response = await apiClient.postData(AppConstants.acceptOrderUri, {
      "_method": "put",
      'token': _getUserToken(),
      'order_id': orderID,
      'lat': locationResult.latitude,
      'lng': locationResult.longitude,
    }, handleError: false);
    if (response.statusCode == 200) {
      responseModel = ResponseModel(true, response.body['message']);
    } else {
      responseModel = ResponseModel(false, response.statusText);
    }
    return responseModel;
  }

  @override
  Future<ResponseModel> rejectOrder(
    int? orderID, {
    required bool expired,
  }) async {
    ResponseModel responseModel;
    Response response = await apiClient.postData(AppConstants.rejectOrderUri, {
      "_method": "put",
      'token': _getUserToken(),
      'order_id': orderID,
      'expired': expired,
    }, handleError: false);
    if (response.statusCode == 200) {
      responseModel = ResponseModel(true, response.body['message']);
    } else {
      responseModel = ResponseModel(false, response.statusText);
    }
    return responseModel;
  }

  @override
  List<IgnoreModel> getIgnoreList() {
    List<IgnoreModel> ignoreList = [];
    List<String> stringList =
        sharedPreferences.getStringList(AppConstants.ignoreList) ?? [];
    for (var ignore in stringList) {
      ignoreList.add(IgnoreModel.fromJson(jsonDecode(ignore)));
    }
    return ignoreList;
  }

  @override
  void setIgnoreList(List<IgnoreModel> ignoreList) {
    List<String> stringList = [];
    for (var ignore in ignoreList) {
      stringList.add(jsonEncode(ignore.toJson()));
    }
    sharedPreferences.setStringList(AppConstants.ignoreList, stringList);
  }

  String _getUserToken() {
    return sharedPreferences.getString(AppConstants.token) ?? "";
  }

  @override
  Future<ParcelCancellationReasonsModel?> getParcelCancellationReasons({
    required bool isBeforePickup,
  }) async {
    ParcelCancellationReasonsModel? cancellationReasonsModel;
    Response response = await apiClient.getData(
      '${AppConstants.getParcelCancellationReasons}?limit=25&offset=1&user_type=customer&cancellation_type=${isBeforePickup ? 'before_pickup' : 'after_pickup'}',
    );
    if (response.statusCode == 200) {
      cancellationReasonsModel = ParcelCancellationReasonsModel.fromJson(
        response.body,
      );
    }
    return cancellationReasonsModel;
  }

  @override
  Future<bool> addParcelReturnDate({
    required int orderId,
    required String returnDate,
  }) async {
    Map<String, dynamic> data = {
      'token': _getUserToken(),
      'order_id': orderId,
      'return_date': returnDate,
    };
    Response response = await apiClient.postData(
      AppConstants.addParcelReturnDate,
      data,
    );
    return response.statusCode == 200;
  }

  @override
  Future<bool> submitParcelReturn({
    required int orderId,
    required String orderStatus,
    required int returnOtp,
  }) async {
    Map<String, dynamic> data = {
      'order_id': orderId,
      'order_status': orderStatus,
      'return_otp': returnOtp,
      'token': _getUserToken(),
    };
    Response response = await apiClient.postData(
      AppConstants.parcelReturn,
      data,
    );
    return response.statusCode == 200;
  }

  @override
  Future<PaginatedOrderModel?> getCurrentOrders(
    int offset, {
    String orderStatus = 'all',
  }) async {
    PaginatedOrderModel? paginatedOrderModel;
    Response response = await apiClient.getData(
      '${AppConstants.currentOrdersUri + _getUserToken()}&offset=$offset&limit=10&order_status=$orderStatus',
      handleError: false,
    );
    if (response.statusCode == 200) {
      paginatedOrderModel = PaginatedOrderModel.fromJson(response.body);
    }
    return paginatedOrderModel;
  }

  @override
  Future<List<OrderCountModel>?> getOrderCount(String type) async {
    List<OrderCountModel>? orderCountList;
    Response response = await apiClient.getData(
      '${AppConstants.orderCount}?type=$type&token=${_getUserToken()}',
      handleError: false,
    );
    if (response.statusCode == 200) {
      orderCountList = (response.body as List)
          .map((item) => OrderCountModel.fromJson(item))
          .toList();
    }
    return orderCountList;
  }

  @override
  Map<String, String> getDeliveryOperationStages() {
    final String rawStages =
        sharedPreferences.getString(AppConstants.deliveryOperationStages) ??
        '{}';
    try {
      final Map<String, dynamic> decoded = jsonDecode(rawStages);
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> setDeliveryOperationStage(int orderId, String stageKey) async {
    final Map<String, String> stages = getDeliveryOperationStages();
    stages[orderId.toString()] = stageKey;
    await sharedPreferences.setString(
      AppConstants.deliveryOperationStages,
      jsonEncode(stages),
    );
  }

  @override
  Future<void> clearDeliveryOperationStage(int orderId) async {
    final Map<String, String> stages = getDeliveryOperationStages();
    stages.remove(orderId.toString());
    await sharedPreferences.setString(
      AppConstants.deliveryOperationStages,
      jsonEncode(stages),
    );
  }

  @override
  double getDeliveryGeofenceRadius() {
    return sharedPreferences.getDouble(AppConstants.deliveryGeofenceRadius) ??
        AppConstants.defaultDeliveryGeofenceRadiusInMeters;
  }

  @override
  Future<void> setDeliveryGeofenceRadius(double radiusInMeters) async {
    await sharedPreferences.setDouble(
      AppConstants.deliveryGeofenceRadius,
      radiusInMeters,
    );
  }

  @override
  Future<void> persistPendingIncomingOffer(OrderModel? orderModel) async {
    if (orderModel == null) {
      await sharedPreferences.remove(AppConstants.pendingIncomingOffer);
      return;
    }
    await sharedPreferences.setString(
      AppConstants.pendingIncomingOffer,
      jsonEncode(orderModel.toJson()),
    );
  }

  @override
  OrderModel? getPersistedPendingIncomingOffer() {
    final String? rawOrder = sharedPreferences.getString(
      AppConstants.pendingIncomingOffer,
    );
    if (rawOrder == null || rawOrder.isEmpty) {
      return null;
    }
    try {
      return OrderModel.fromJson(jsonDecode(rawOrder));
    } catch (_) {
      sharedPreferences.remove(AppConstants.pendingIncomingOffer);
      return null;
    }
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
  Future update(Map<String, dynamic> body) {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> getList() {
    throw UnimplementedError();
  }
}
