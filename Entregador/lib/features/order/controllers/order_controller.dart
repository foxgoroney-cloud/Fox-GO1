import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:fox_delivery_driver/common/models/response_model.dart';
import 'package:fox_delivery_driver/common/models/config_model.dart';
import 'package:fox_delivery_driver/features/order/domain/models/delivery_operation_stage.dart';
import 'package:fox_delivery_driver/features/order/domain/models/order_count_model.dart';
import 'package:fox_delivery_driver/features/order/domain/models/parcel_cancellation_reasons_model.dart';
import 'package:fox_delivery_driver/features/profile/controllers/profile_controller.dart';
import 'package:fox_delivery_driver/features/auth/controllers/auth_controller.dart';
import 'package:fox_delivery_driver/features/splash/controllers/splash_controller.dart';
import 'package:fox_delivery_driver/api/api_client.dart';
import 'package:fox_delivery_driver/features/order/domain/models/order_details_model.dart';
import 'package:fox_delivery_driver/features/order/domain/models/order_model.dart';
import 'package:fox_delivery_driver/features/order/domain/models/update_status_body_model.dart';
import 'package:fox_delivery_driver/features/order/domain/models/ignore_model.dart';
import 'package:fox_delivery_driver/features/order/domain/models/order_cancellation_body.dart';
import 'package:fox_delivery_driver/helper/route_helper.dart';
import 'package:fox_delivery_driver/helper/custom_print_helper.dart';
import 'package:fox_delivery_driver/util/app_constants.dart';
import 'package:fox_delivery_driver/common/widgets/custom_snackbar_widget.dart';
import 'package:get/get.dart';
import 'package:fox_delivery_driver/features/order/domain/services/order_service_interface.dart';

class OrderController extends GetxController implements GetxService {
  final OrderServiceInterface orderServiceInterface;
  OrderController({required this.orderServiceInterface}) {
    _hydrateOperationalSettings();
  }

  List<OrderModel>? _currentOrderList;
  List<OrderModel>? get currentOrderList => _currentOrderList;

  List<OrderModel>? _completedOrderList;
  List<OrderModel>? get completedOrderList => _completedOrderList;

  List<OrderModel>? _latestOrderList;
  OrderModel? _incomingOfferOrder;
  List<OrderModel>? get latestOrderList => _latestOrderList;
  OrderModel? get incomingOfferOrder => _incomingOfferOrder;

  List<OrderDetailsModel>? _orderDetailsModel;
  List<OrderDetailsModel>? get orderDetailsModel => _orderDetailsModel;

  List<IgnoreModel> _ignoredRequests = [];
  List<IgnoreModel> get ignoredRequests => _ignoredRequests;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _otp = '';
  String get otp => _otp;

  bool _paginate = false;
  bool get paginate => _paginate;

  int? _pageSize;
  int? get pageSize => _pageSize;

  List<int> _offsetList = [];
  List<int> get offsetList => _offsetList;

  int _offset = 1;
  int get offset => _offset;

  OrderModel? _orderModel;
  OrderModel? get orderModel => _orderModel;

  String? _cancelReason = '';
  String? get cancelReason => _cancelReason;

  List<CancellationData>? _orderCancelReasons;
  List<CancellationData>? get orderCancelReasons => _orderCancelReasons;

  bool _showDeliveryImageField = false;
  bool get showDeliveryImageField => _showDeliveryImageField;

  List<XFile> _pickedPrescriptions = [];
  List<XFile> get pickedPrescriptions => _pickedPrescriptions;

  List<Reason>? _parcelCancellationReasons;
  List<Reason>? get parcelCancellationReasons => _parcelCancellationReasons;

  final List<String> _selectedParcelCancelReason = [];
  List<String>? get selectedParcelCancelReason => _selectedParcelCancelReason;

  DateTime? _selectedDate;
  DateTime? get selectedDate => _selectedDate;

  int _selectedHour = 11;
  int get selectedHour => _selectedHour;

  int _selectedMinute = 59;
  int get selectedMinute => _selectedMinute;

  String _selectedPeriod = 'PM';
  String get selectedPeriod => _selectedPeriod;

  final List<DateTime> _availableDates = [];
  List<DateTime> get availableDates => _availableDates;

  List<OrderCountModel>? _currentOrderCountList;
  List<OrderCountModel>? get currentOrderCountList => _currentOrderCountList;

  List<OrderCountModel>? _historyOrderCountList;
  List<OrderCountModel>? get historyOrderCountList => _historyOrderCountList;

  String _selectedHistoryStatus = 'all';
  String get selectedHistoryStatus => _selectedHistoryStatus;

  String _selectedRunningStatus = 'all';
  String get selectedRunningStatus => _selectedRunningStatus;

  String _orderType = 'current';
  String get orderType => _orderType;

  final Map<int, DeliveryOperationStage> _deliveryOperationStages = {};
  Map<int, DeliveryOperationStage> get deliveryOperationStages =>
      _deliveryOperationStages;

  double _deliveryGeofenceRadiusInMeters =
      AppConstants.defaultDeliveryGeofenceRadiusInMeters;
  double get deliveryGeofenceRadiusInMeters => _deliveryGeofenceRadiusInMeters;

  int? _activeOperationalOrderId;
  int? get activeOperationalOrderId => _activeOperationalOrderId;

  void _hydrateOperationalSettings() {
    _deliveryOperationStages.clear();
    orderServiceInterface.getDeliveryOperationStages().forEach((
      orderId,
      stageKey,
    ) {
      final int? parsedOrderId = int.tryParse(orderId);
      if (parsedOrderId != null) {
        _deliveryOperationStages[parsedOrderId] = deliveryOperationStageFromKey(
          stageKey,
        );
      }
    });
    _deliveryGeofenceRadiusInMeters = orderServiceInterface
        .getDeliveryGeofenceRadius();
    if (Get.isRegistered<SplashController>()) {
      syncDeliveryGeofenceRadiusFromConfig(
        Get.find<SplashController>().configModel,
        shouldUpdate: false,
      );
    }
  }

  Future<void> setDeliveryGeofenceRadius(double radiusInMeters) async {
    _deliveryGeofenceRadiusInMeters = radiusInMeters;
    await orderServiceInterface.setDeliveryGeofenceRadius(radiusInMeters);
    update();
  }

  void syncDeliveryGeofenceRadiusFromConfig(
    ConfigModel? configModel, {
    bool shouldUpdate = true,
  }) {
    final double configuredRadius = configModel?.deliverymanGeofenceRadius ?? 0;
    if (configuredRadius <= 0 ||
        (configuredRadius - _deliveryGeofenceRadiusInMeters).abs() < 0.01) {
      return;
    }

    _deliveryGeofenceRadiusInMeters = configuredRadius;
    orderServiceInterface.setDeliveryGeofenceRadius(configuredRadius);
    if (shouldUpdate) {
      update();
    }
  }

  void setActiveOperationalOrder(int? orderId, {bool shouldUpdate = true}) {
    _activeOperationalOrderId = orderId;
    if (shouldUpdate) {
      update();
    }
  }

  DeliveryOperationStage deriveOperationalStageFromOrder(OrderModel order) {
    final DeliveryOperationStage? persistedStage = order.id != null
        ? _deliveryOperationStages[order.id!]
        : null;

    if (order.orderStatus == AppConstants.delivered) {
      return DeliveryOperationStage.deliveryCompleted;
    }

    if (order.orderStatus == AppConstants.pickedUp) {
      if (persistedStage == DeliveryOperationStage.arrivedAtCustomer ||
          persistedStage == DeliveryOperationStage.awaitingDeliveryCode ||
          persistedStage == DeliveryOperationStage.deliveryCompleted) {
        return persistedStage!;
      }
      if (persistedStage == DeliveryOperationStage.pickupConfirmed) {
        return DeliveryOperationStage.pickupConfirmed;
      }
      return DeliveryOperationStage.onTheWayToCustomer;
    }

    if (order.orderStatus == AppConstants.handover) {
      if (persistedStage == DeliveryOperationStage.pickupConfirmation ||
          persistedStage == DeliveryOperationStage.pickupConfirmed ||
          persistedStage == DeliveryOperationStage.onTheWayToCustomer ||
          persistedStage == DeliveryOperationStage.arrivedAtCustomer ||
          persistedStage == DeliveryOperationStage.awaitingDeliveryCode) {
        return persistedStage!;
      }
      if (persistedStage == DeliveryOperationStage.arrivedAtStore ||
          persistedStage == DeliveryOperationStage.waitingStoreReady) {
        return persistedStage!;
      }
      return DeliveryOperationStage.waitingStoreReady;
    }

    if (persistedStage == DeliveryOperationStage.arrivedAtStore ||
        persistedStage == DeliveryOperationStage.waitingStoreReady ||
        persistedStage == DeliveryOperationStage.pickupConfirmation) {
      return persistedStage!;
    }

    return DeliveryOperationStage.onTheWayToStore;
  }

  DeliveryOperationStage getOperationalStageForOrder(OrderModel order) {
    return deriveOperationalStageFromOrder(order);
  }

  Future<void> initializeOperationalFlow(
    OrderModel order, {
    bool shouldUpdate = true,
  }) async {
    if (order.id == null) {
      return;
    }
    setActiveOperationalOrder(order.id, shouldUpdate: false);
    await setOperationalStage(
      order.id!,
      deriveOperationalStageFromOrder(order),
      shouldUpdate: shouldUpdate,
    );
  }

  Future<void> setOperationalStage(
    int orderId,
    DeliveryOperationStage stage, {
    bool shouldUpdate = true,
  }) async {
    _deliveryOperationStages[orderId] = stage;
    await orderServiceInterface.setDeliveryOperationStage(orderId, stage.key);
    if (shouldUpdate) {
      update();
    }
  }

  Future<void> clearOperationalStage(
    int orderId, {
    bool shouldUpdate = true,
  }) async {
    _deliveryOperationStages.remove(orderId);
    await orderServiceInterface.clearDeliveryOperationStage(orderId);
    if (_activeOperationalOrderId == orderId) {
      _activeOperationalOrderId = null;
    }
    if (shouldUpdate) {
      update();
    }
  }

  Future<void> cleanupOperationalStages(List<OrderModel> currentOrders) async {
    final Set<int> activeOrderIds = currentOrders
        .map((order) => order.id)
        .whereType<int>()
        .toSet();
    final List<int> staleOrderIds = _deliveryOperationStages.keys
        .where((orderId) => !activeOrderIds.contains(orderId))
        .toList();
    for (final int orderId in staleOrderIds) {
      await clearOperationalStage(orderId, shouldUpdate: false);
    }
    update();
  }

  String getOperationalStatusLabel(DeliveryOperationStage stage) {
    switch (stage) {
      case DeliveryOperationStage.idle:
        return 'Aguardando novo pedido';
      case DeliveryOperationStage.onTheWayToStore:
        return 'A caminho da loja';
      case DeliveryOperationStage.arrivedAtStore:
        return 'Cheguei na loja';
      case DeliveryOperationStage.waitingStoreReady:
        return 'Aguardando pedido pronto';
      case DeliveryOperationStage.pickupConfirmation:
        return 'ConfirmaÃ§Ã£o de coleta';
      case DeliveryOperationStage.pickupConfirmed:
        return 'Retirada confirmada';
      case DeliveryOperationStage.onTheWayToCustomer:
        return 'A caminho do cliente';
      case DeliveryOperationStage.arrivedAtCustomer:
        return 'Cheguei no cliente';
      case DeliveryOperationStage.awaitingDeliveryCode:
        return 'Aguardando cÃ³digo de entrega';
      case DeliveryOperationStage.deliveryCompleted:
        return 'Entrega concluÃ­da';
    }
  }

  String getPickupReference(OrderModel order) {
    final String? transactionReference = order.transactionReference?.trim();
    if (transactionReference != null && transactionReference.isNotEmpty) {
      return transactionReference;
    }

    final String orderReference = (order.id ?? 0).toString().padLeft(4, '0');
    return orderReference.substring(max(orderReference.length - 4, 0));
  }

  double? getCachedDistanceToDestination({
    required OrderModel order,
    required bool useStoreDestination,
  }) {
    final OperationalDestination destination = useStoreDestination
        ? _getStoreDestination(order)
        : _getCustomerDestination(order);

    if (!destination.isValid) {
      return null;
    }

    final recordLocation = Get.find<ProfileController>().recordLocationBody;
    if (recordLocation?.latitude == null || recordLocation?.longitude == null) {
      return null;
    }

    return Geolocator.distanceBetween(
      recordLocation!.latitude!,
      recordLocation.longitude!,
      destination.latitude,
      destination.longitude,
    );
  }

  String formatOperationalDistance(double distanceInMeters) {
    if (distanceInMeters >= 1000) {
      return '${(distanceInMeters / 1000).toStringAsFixed(distanceInMeters >= 10000 ? 0 : 1)} km';
    }

    return '${distanceInMeters.round()} m';
  }

  Future<GeofenceValidationResult> validateOperationalGeofence({
    required OrderModel order,
    required bool useStoreDestination,
  }) async {
    final OperationalDestination destination = useStoreDestination
        ? _getStoreDestination(order)
        : _getCustomerDestination(order);

    if (!destination.isValid) {
      throw const OperationalLocationException(
        'Nao foi possivel validar a localizacao deste destino.',
      );
    }

    final ({double latitude, double longitude}) currentCoordinates =
        await _resolveCurrentCoordinates();

    final double distanceMeters = Geolocator.distanceBetween(
      currentCoordinates.latitude,
      currentCoordinates.longitude,
      destination.latitude,
      destination.longitude,
    );

    return GeofenceValidationResult(
      allowed: distanceMeters <= _deliveryGeofenceRadiusInMeters,
      distanceMeters: distanceMeters,
      allowedRadiusMeters: _deliveryGeofenceRadiusInMeters,
    );
  }

  String buildGeofenceFailureMessage({
    required GeofenceValidationResult result,
    required bool isCustomerDestination,
  }) {
    final int missingMeters = result.remainingMeters.ceil();
    final int allowedRadius = _deliveryGeofenceRadiusInMeters.round();
    if (isCustomerDestination) {
      return 'VocÃª precisa estar a no mÃ¡ximo $allowedRadius metros do cliente para concluir esta etapa.\nFaltam $missingMeters metros para chegar ao local.';
    }
    return 'VocÃª ainda estÃ¡ fora da Ã¡rea permitida para esta aÃ§Ã£o.\nFaltam $missingMeters metros para chegar ao local.';
  }

  Future<bool> confirmArrivalAtStore(OrderModel order) async {
    final GeofenceValidationResult? result = await _runGeofenceGuard(
      order: order,
      useStoreDestination: true,
      isCustomerDestination: false,
    );
    if (result == null) {
      return false;
    }

    await setOperationalStage(order.id!, DeliveryOperationStage.arrivedAtStore);
    showCustomSnackBar('Chegada na loja confirmada.', isError: false);
    return true;
  }

  Future<bool> startPickupConfirmation(OrderModel order) async {
    final GeofenceValidationResult? result = await _runGeofenceGuard(
      order: order,
      useStoreDestination: true,
      isCustomerDestination: false,
    );
    if (result == null) {
      return false;
    }

    await setOperationalStage(
      order.id!,
      DeliveryOperationStage.pickupConfirmation,
    );
    return true;
  }

  Future<bool> confirmPickup(OrderModel order) async {
    if (Get.find<ProfileController>().profileModel?.active != 1) {
      showCustomSnackBar('Fique online para continuar a entrega.');
      return false;
    }

    final GeofenceValidationResult? result = await _runGeofenceGuard(
      order: order,
      useStoreDestination: true,
      isCustomerDestination: false,
    );
    if (result == null) {
      return false;
    }

    final bool success = await updateOrderStatus(
      order,
      AppConstants.pickedUp,
      closeDialog: false,
    );

    if (success && order.id != null) {
      await setOperationalStage(
        order.id!,
        DeliveryOperationStage.pickupConfirmed,
      );
    }
    return success;
  }

  Future<bool> confirmArrivalAtCustomer(OrderModel order) async {
    final GeofenceValidationResult? result = await _runGeofenceGuard(
      order: order,
      useStoreDestination: false,
      isCustomerDestination: true,
    );
    if (result == null) {
      return false;
    }

    await setOperationalStage(
      order.id!,
      DeliveryOperationStage.arrivedAtCustomer,
    );
    showCustomSnackBar('Chegada no cliente confirmada.', isError: false);
    return true;
  }

  Future<bool> confirmDeliveryWithCode(
    OrderModel order,
    String deliveryCode,
  ) async {
    final String normalizedCode = deliveryCode.trim();
    if (normalizedCode.length != 4) {
      showCustomSnackBar(
        'CÃ³digo do cliente invÃ¡lido. Digite os 4 nÃºmeros corretamente.',
      );
      return false;
    }

    final GeofenceValidationResult? result = await _runGeofenceGuard(
      order: order,
      useStoreDestination: false,
      isCustomerDestination: true,
    );
    if (result == null) {
      return false;
    }

    setOtp(normalizedCode);
    final bool success = await updateOrderStatus(
      order,
      AppConstants.delivered,
      closeDialog: false,
    );

    if (success && order.id != null) {
      await setOperationalStage(
        order.id!,
        DeliveryOperationStage.deliveryCompleted,
      );
    }
    return success;
  }

  Future<GeofenceValidationResult?> _runGeofenceGuard({
    required OrderModel order,
    required bool useStoreDestination,
    required bool isCustomerDestination,
  }) async {
    try {
      final GeofenceValidationResult result = await validateOperationalGeofence(
        order: order,
        useStoreDestination: useStoreDestination,
      );

      if (!result.allowed) {
        showCustomSnackBar(
          buildGeofenceFailureMessage(
            result: result,
            isCustomerDestination: isCustomerDestination,
          ),
        );
        return null;
      }

      return result;
    } on OperationalLocationException catch (exception) {
      showCustomSnackBar(exception.message);
      return null;
    } catch (_) {
      showCustomSnackBar(
        'Nao foi possivel validar sua localizacao agora. Tente novamente.',
      );
      return null;
    }
  }

  Future<({double latitude, double longitude})>
  _resolveCurrentCoordinates() async {
    final recordLocation = Get.find<ProfileController>().recordLocationBody;
    if (recordLocation?.latitude != null && recordLocation?.longitude != null) {
      return (
        latitude: recordLocation!.latitude!,
        longitude: recordLocation.longitude!,
      );
    }

    final bool isServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isServiceEnabled) {
      throw const OperationalLocationException(
        'Ative o GPS para continuar com esta etapa.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const OperationalLocationException(
        'Permita o acesso a localizacao para continuar com esta etapa.',
      );
    }

    final Position currentPosition = await Geolocator.getCurrentPosition();
    return (
      latitude: currentPosition.latitude,
      longitude: currentPosition.longitude,
    );
  }

  OperationalDestination _getStoreDestination(OrderModel order) {
    return OperationalDestination(
      latitude: double.tryParse(order.storeLat ?? '') ?? 0,
      longitude: double.tryParse(order.storeLng ?? '') ?? 0,
    );
  }

  OperationalDestination _getCustomerDestination(OrderModel order) {
    final DeliveryAddress? customerAddress =
        order.orderType == 'parcel' && order.receiverDetails != null
        ? order.receiverDetails
        : order.deliveryAddress;

    return OperationalDestination(
      latitude: double.tryParse(customerAddress?.latitude ?? '') ?? 0,
      longitude: double.tryParse(customerAddress?.longitude ?? '') ?? 0,
    );
  }

  void changeDeliveryImageStatus({bool isUpdate = true}) {
    _showDeliveryImageField = !_showDeliveryImageField;
    if (isUpdate) {
      update();
    }
  }

  void pickPrescriptionImage({
    required bool isRemove,
    required bool isCamera,
  }) async {
    if (isRemove) {
      _pickedPrescriptions = [];
    } else {
      XFile? xFile = await ImagePicker().pickImage(
        source: isCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 50,
      );
      if (xFile != null) {
        _pickedPrescriptions.add(xFile);
        if (Get.isDialogOpen!) {
          Get.back();
        }
      }
      update();
    }
  }

  void initLoading() {
    _isLoading = false;
    update();
  }

  void setOrderCancelReason(String? reason) {
    _cancelReason = reason;
    update();
  }

  Future<void> getOrderCancelReasons() async {
    List<CancellationData>? orderCancelReasons = await orderServiceInterface
        .getCancelReasons();
    if (orderCancelReasons != null) {
      _orderCancelReasons = [];
      _orderCancelReasons!.addAll(orderCancelReasons);
    }
    update();
  }

  Future<void> getOrderWithId(
    int? orderId, {
    bool popScreenOnError = true,
  }) async {
    _orderModel = null;
    Response response = await orderServiceInterface.getOrderWithId(orderId);
    if (response.statusCode == 200) {
      _orderModel = OrderModel.fromJson(response.body);

      debugPrint(_orderModel.toString());
    } else {
      if (popScreenOnError &&
          Get.context != null &&
          Navigator.canPop(Get.context!)) {
        Navigator.pop(Get.context!);
      }
      await Get.find<OrderController>().getRunningOrders(offset);
    }
    update();
  }

  Future<void> getCompletedOrders(
    int offset, {
    bool willUpdate = true,
    String? status,
  }) async {
    String orderStatus = status ?? _selectedHistoryStatus;

    if (offset == 1) {
      _offsetList = [];
      _offset = 1;
      _completedOrderList = null;
      if (willUpdate) {
        update();
      }
    }
    if (!_offsetList.contains(offset)) {
      _offsetList.add(offset);
      PaginatedOrderModel? paginatedOrderModel = await orderServiceInterface
          .getCompletedOrderList(offset, orderStatus: orderStatus);
      if (paginatedOrderModel != null) {
        if (offset == 1) {
          _completedOrderList = [];
        }
        _completedOrderList!.addAll(paginatedOrderModel.orders!);
        _pageSize = paginatedOrderModel.totalSize;
        _paginate = false;
        update();
      }
    } else {
      if (_paginate) {
        _paginate = false;
        update();
      }
    }
  }

  void showBottomLoader() {
    _paginate = true;
    update();
  }

  void setOffset(int offset) {
    _offset = offset;
  }

  Future<void> getRunningOrders(
    int offset, {
    bool willUpdate = true,
    String? status,
  }) async {
    String orderStatus = status ?? _selectedRunningStatus;
    if (status != null) {
      _selectedRunningStatus = status;
    }

    if (offset == 1) {
      _offsetList = [];
      _offset = 1;
      _completedOrderList = null;
      if (willUpdate) {
        update();
      }
    }
    if (!_offsetList.contains(offset)) {
      _offsetList.add(offset);
      PaginatedOrderModel? paginatedOrderModel = await orderServiceInterface
          .getCurrentOrders(offset, orderStatus: orderStatus);
      if (paginatedOrderModel != null) {
        if (offset == 1) {
          _currentOrderList = [];
        }
        _currentOrderList!.addAll(paginatedOrderModel.orders!);
        if (offset == 1) {
          await cleanupOperationalStages(_currentOrderList!);
        }
        _pageSize = paginatedOrderModel.totalSize;
        _paginate = false;
        update();
      } else {
        if (_paginate) {
          _paginate = false;
          update();
        }
      }
    }
  }

  Future<void> getLatestOrders() async {
    List<OrderModel>? latestOrderList = await orderServiceInterface
        .getLatestOrders();
    if (latestOrderList != null) {
      _latestOrderList = [];
      List<int?> ignoredIdList = orderServiceInterface.prepareIgnoreIdList(
        _ignoredRequests,
      );
      _latestOrderList!.addAll(
        orderServiceInterface.processLatestOrders(
          latestOrderList,
          ignoredIdList,
        ),
      );
      await _validatePendingOfferStateWithLatestOrders(shouldUpdate: false);
      await _syncIncomingOfferFromLatestOrders(
        shouldNavigateToHome: _incomingOfferOrder == null,
      );
    }
    update();
  }

  Future<bool> updateOrderStatus(
    OrderModel currentOrder,
    String status, {
    bool back = false,
    String? reason,
    bool? parcel = false,
    bool gotoDashboard = false,
    List<String>? reasons,
    String? comment,
    bool stopOtherDataCall = false,
    bool closeDialog = true,
  }) async {
    _isLoading = true;
    update();
    List<MultipartBody> multiParts = orderServiceInterface
        .prepareOrderProofImages(_pickedPrescriptions);
    UpdateStatusBodyModel updateStatusBody = UpdateStatusBodyModel(
      orderId: currentOrder.id,
      status: status,
      reason: reason,
      otp:
          status == AppConstants.delivered ||
              (parcel! && status == AppConstants.pickedUp)
          ? _otp
          : null,
      isParcel: parcel,
      comment: comment,
      reasons: reasons,
    );
    ResponseModel responseModel = await orderServiceInterface.updateOrderStatus(
      updateStatusBody,
      multiParts,
    );
    if (closeDialog &&
        ((Get.isDialogOpen ?? false) || (Get.isBottomSheetOpen ?? false))) {
      Get.back(result: responseModel.isSuccess);
    }
    if (responseModel.isSuccess) {
      if (back) {
        Get.back();
      }
      if (gotoDashboard) {
        Get.offAllNamed(RouteHelper.getInitialRoute(fromOrderDetails: true));
      }
      if (!stopOtherDataCall) {
        Get.find<ProfileController>().getProfile();

        // Auto-reset to 'all' for handover and post-handover status changes
        List<String> autoResetStatuses = ['picked_up'];
        if (autoResetStatuses.contains(currentOrder.orderStatus) &&
            _selectedRunningStatus != 'all') {
          _selectedRunningStatus = 'all';
        }

        getRunningOrders(offset);
        getOrderCount('current');
        currentOrder.orderStatus = status;
      }
      if (status == AppConstants.delivered && currentOrder.id != null) {
        await clearOperationalStage(currentOrder.id!, shouldUpdate: false);
      }
      showCustomSnackBar(
        responseModel.message,
        isError: false,
        getXSnackBar: false,
      );
    } else {
      showCustomSnackBar(
        responseModel.message,
        isError: true,
        getXSnackBar: false,
      );
    }
    _isLoading = false;
    update();
    return responseModel.isSuccess;
  }

  Future<void> getOrderDetails(int? orderID, bool parcel) async {
    if (parcel) {
      _orderDetailsModel = [];
    } else {
      _orderDetailsModel = null;
      List<OrderDetailsModel>? orderDetailsModel = await orderServiceInterface
          .getOrderDetails(orderID);
      if (orderDetailsModel != null) {
        _orderDetailsModel = [];
        _orderDetailsModel!.addAll(orderDetailsModel);
      }
      update();
    }
  }

  Future<bool> acceptOrder(
    int? orderID,
    int index,
    OrderModel orderModel, {
    bool closeDialog = true,
  }) async {
    _isLoading = true;
    update();
    ResponseModel responseModel = await orderServiceInterface.acceptOrder(
      orderID,
    );
    if (closeDialog && Get.isDialogOpen == true) {
      Get.back();
    }
    if (responseModel.isSuccess) {
      _latestOrderList!.removeAt(index);
      _currentOrderList ??= [];
      _currentOrderList!.add(orderModel);
      await clearPendingIncomingOffer(shouldUpdate: false);
    } else {
      showCustomSnackBar(responseModel.message, isError: true);
    }
    _isLoading = false;
    update();
    return responseModel.isSuccess;
  }

  Future<bool> rejectOrder(int index, {bool expired = false}) async {
    if (_latestOrderList == null ||
        index < 0 ||
        index >= _latestOrderList!.length) {
      await clearPendingIncomingOffer(shouldUpdate: false);
      update();
      return false;
    }

    final OrderModel orderModel = _latestOrderList![index];
    _isLoading = true;
    update();

    ResponseModel? responseModel;
    if (orderModel.dispatchOfferActive == true) {
      responseModel = await orderServiceInterface.rejectOrder(
        orderModel.id,
        expired: expired,
      );
      final int? pendingOrderId = orderModel.id;
      _latestOrderList!.removeAt(index);
      if (_incomingOfferOrder?.id == pendingOrderId) {
        await clearPendingIncomingOffer(shouldUpdate: false);
      }
    } else {
      ignoreOrder(index);
    }
    await getLatestOrders();

    if (responseModel != null && !responseModel.isSuccess && !expired) {
      showCustomSnackBar(responseModel.message, isError: true);
    }

    _isLoading = false;
    update();
    return responseModel?.isSuccess ?? true;
  }

  void getIgnoreList() {
    _ignoredRequests = [];
    _ignoredRequests.addAll(orderServiceInterface.getIgnoreList());
  }

  void ignoreOrder(int index) {
    final int? ignoredOrderId = _latestOrderList?[index].id;
    _ignoredRequests.add(
      IgnoreModel(id: _latestOrderList![index].id, time: DateTime.now()),
    );
    _latestOrderList!.removeAt(index);
    orderServiceInterface.setIgnoreList(_ignoredRequests);
    if (_incomingOfferOrder?.id == ignoredOrderId) {
      clearPendingIncomingOffer(shouldUpdate: false);
    }
    update();
  }

  void setIncomingOfferOrder(OrderModel? orderModel) {
    final bool listChanged = orderModel != null
        ? _upsertLatestIncomingOffer(orderModel)
        : false;
    final bool isSameOffer =
        _incomingOfferOrder?.id == orderModel?.id &&
        _incomingOfferOrder?.orderStatus == orderModel?.orderStatus &&
        _incomingOfferOrder?.updatedAt == orderModel?.updatedAt &&
        _incomingOfferOrder?.dispatchOfferActive ==
            orderModel?.dispatchOfferActive &&
        _incomingOfferOrder?.dispatchOfferExpiresAt ==
            orderModel?.dispatchOfferExpiresAt;
    if (isSameOffer) {
      if (listChanged) {
        update();
      }
      return;
    }
    _incomingOfferOrder = orderModel;
    orderServiceInterface.persistPendingIncomingOffer(orderModel);
    update();
  }

  Future<void> handleIncomingOfferFromPush({
    required Map<String, dynamic> payload,
    bool shouldNavigateToHome = false,
  }) async {
    customPrint('[PushFlow] handleIncomingOfferFromPush payload=$payload');
    if (!await _canReceiveIncomingOffer()) {
      customPrint(
        '[PushFlow] Entregador offline/nÃ£o autenticado, limpando oferta pendente.',
      );
      await clearPendingIncomingOffer();
      return;
    }

    final int? orderId = _extractOrderId(payload);
    customPrint('[PushFlow] order_id resolvido=$orderId');
    await getLatestOrders();
    OrderModel? resolvedOffer;

    if (orderId != null) {
      resolvedOffer = _findLatestOrderById(orderId);
      resolvedOffer ??= await _fetchOfferByOrderIdFallback(orderId);
      resolvedOffer ??= _buildIncomingOfferFromPayload(payload, orderId);
    }
    resolvedOffer ??= _latestOrderList?.isNotEmpty == true
        ? _latestOrderList!.first
        : null;

    if (resolvedOffer == null) {
      customPrint('[PushFlow] Nenhuma oferta encontrada para renderizar card.');
      await clearPendingIncomingOffer();
      return;
    }

    customPrint(
      '[PushFlow] Oferta resolvida id=${resolvedOffer.id} â€” preparando exibiÃ§Ã£o na Home.',
    );
    if (Get.isDialogOpen == true || Get.isBottomSheetOpen == true) {
      customPrint(
        '[PushFlow] Modal aberto detectado. Fechando antes de renderizar card.',
      );
      Get.back();
    }
    setIncomingOfferOrder(resolvedOffer);
    customPrint('[PushFlow] Oferta pendente setada no controller.');
    update();
    customPrint('[PushFlow] update() chamado no OrderController.');
    if (shouldNavigateToHome) {
      customPrint(
        '[PushFlow] Navegando para Home para garantir card visÃ­vel.',
      );
      Get.offAllNamed(RouteHelper.getMainRoute('home'));
    }
  }

  Future<void> restorePendingIncomingOffer() async {
    if (!await _canReceiveIncomingOffer()) {
      await clearPendingIncomingOffer();
      return;
    }

    final OrderModel? persistedOffer = orderServiceInterface
        .getPersistedPendingIncomingOffer();
    if (persistedOffer != null) {
      _incomingOfferOrder = persistedOffer;
    }
    await getLatestOrders();
  }

  Future<void> syncPendingIncomingOfferWithServer() async {
    if (!await _canReceiveIncomingOffer()) {
      await clearPendingIncomingOffer();
      return;
    }
    await getLatestOrders();
  }

  Future<void> clearPendingIncomingOffer({bool shouldUpdate = true}) async {
    _incomingOfferOrder = null;
    await orderServiceInterface.persistPendingIncomingOffer(null);
    if (shouldUpdate) {
      update();
    }
  }

  Future<bool> canReceiveIncomingOffer() async {
    return _canReceiveIncomingOffer();
  }

  Future<bool> _canReceiveIncomingOffer() async {
    final bool isAuthenticated = Get.find<AuthController>().isLoggedIn();
    final ProfileController profileController = Get.find<ProfileController>();
    int? activeStatus = profileController.profileModel?.active;
    if (activeStatus == null) {
      await profileController.getProfile();
      activeStatus = profileController.profileModel?.active;
    }
    final bool isOnline = activeStatus == 1;
    customPrint(
      '[PushFlow] canReceiveIncomingOffer -> auth=$isAuthenticated online=$isOnline(active=$activeStatus)',
    );
    return isAuthenticated && isOnline;
  }

  int? _extractOrderId(Map<String, dynamic> payload) {
    final dynamic rawOrderId =
        payload['order_id'] ??
        payload['orderId'] ??
        payload['id'] ??
        payload['order'];
    return int.tryParse(rawOrderId?.toString() ?? '');
  }

  Future<OrderModel?> _fetchOfferByOrderIdFallback(int orderId) async {
    customPrint(
      '[PushFlow] Oferta nÃ£o encontrada na latest list. Buscando via API por order_id=$orderId',
    );
    final Response response = await orderServiceInterface.getOrderWithId(
      orderId,
    );
    if (response.statusCode != 200) {
      customPrint(
        '[PushFlow] Falha na busca de detalhes da oferta. status=${response.statusCode}',
      );
      return null;
    }
    return _parseOrderFromUnknownPayload(response.body);
  }

  OrderModel? _parseOrderFromUnknownPayload(dynamic body) {
    if (body is Map<String, dynamic>) {
      final dynamic orderNode =
          body['order'] ??
          body['data'] ??
          body['orders'] ??
          body['order_request'];
      if (orderNode is Map<String, dynamic>) {
        return OrderModel.fromJson(orderNode);
      }
      if (orderNode is List &&
          orderNode.isNotEmpty &&
          orderNode.first is Map<String, dynamic>) {
        return OrderModel.fromJson(orderNode.first as Map<String, dynamic>);
      }
    } else if (body is List &&
        body.isNotEmpty &&
        body.first is Map<String, dynamic>) {
      return OrderModel.fromJson(body.first as Map<String, dynamic>);
    }
    return null;
  }

  Future<void> _validatePendingOfferStateWithLatestOrders({
    bool shouldUpdate = true,
  }) async {
    if (_incomingOfferOrder == null) {
      return;
    }
    final int? pendingOrderId = _incomingOfferOrder?.id;
    if (pendingOrderId == null) {
      await clearPendingIncomingOffer(shouldUpdate: shouldUpdate);
      return;
    }

    final OrderModel? refreshedOffer = _findLatestOrderById(pendingOrderId);
    if (refreshedOffer == null) {
      await clearPendingIncomingOffer(shouldUpdate: shouldUpdate);
      return;
    }
    if (refreshedOffer.dispatchOfferActive != true) {
      await clearPendingIncomingOffer(shouldUpdate: shouldUpdate);
      return;
    }

    _incomingOfferOrder = refreshedOffer;
    await orderServiceInterface.persistPendingIncomingOffer(refreshedOffer);
    if (shouldUpdate) {
      update();
    }
  }

  Future<void> _syncIncomingOfferFromLatestOrders({
    bool shouldNavigateToHome = false,
  }) async {
    if (!await _canReceiveIncomingOffer()) {
      return;
    }

    OrderModel? targetedOffer;
    for (final OrderModel order in _latestOrderList ?? <OrderModel>[]) {
      if (order.dispatchOfferActive == true) {
        targetedOffer = order;
        break;
      }
    }

    if (targetedOffer == null) {
      return;
    }

    final bool isSameOffer =
        _incomingOfferOrder?.id == targetedOffer.id &&
        _incomingOfferOrder?.dispatchOfferExpiresAt ==
            targetedOffer.dispatchOfferExpiresAt &&
        _incomingOfferOrder?.updatedAt == targetedOffer.updatedAt;
    if (isSameOffer) {
      return;
    }

    setIncomingOfferOrder(targetedOffer);
    if (shouldNavigateToHome &&
        Get.currentRoute != RouteHelper.getMainRoute('home')) {
      Get.offAllNamed(RouteHelper.getMainRoute('home'));
    }
  }

  OrderModel? _findLatestOrderById(int id) {
    if (_latestOrderList == null) {
      return null;
    }
    for (final OrderModel order in _latestOrderList!) {
      if (order.id == id) {
        return order;
      }
    }
    return null;
  }

  bool _upsertLatestIncomingOffer(OrderModel orderModel) {
    final int? orderId = orderModel.id;
    if (orderId != null) {
      _ignoredRequests.removeWhere((IgnoreModel item) => item.id == orderId);
      orderServiceInterface.setIgnoreList(_ignoredRequests);
    }

    _latestOrderList ??= <OrderModel>[];

    final int existingIndex = _latestOrderList!.indexWhere(
      (OrderModel item) => item.id == orderId,
    );

    if (existingIndex == 0) {
      _latestOrderList![0] = orderModel;
      return true;
    }

    if (existingIndex > 0) {
      _latestOrderList!.removeAt(existingIndex);
      _latestOrderList!.insert(0, orderModel);
      return true;
    }

    _latestOrderList!.insert(0, orderModel);
    return true;
  }

  OrderModel _buildIncomingOfferFromPayload(
    Map<String, dynamic> payload,
    int orderId,
  ) {
    final String title =
        (payload['title']?.toString().trim().isNotEmpty ?? false)
        ? payload['title'].toString().trim()
        : 'Nova entrega disponivel';
    final String description =
        (payload['body']?.toString().trim().isNotEmpty ?? false)
        ? payload['body'].toString().trim()
        : 'Abra a oferta para atualizar os detalhes';
    final String orderType =
        (payload['order_type']?.toString().trim().isNotEmpty ?? false)
        ? payload['order_type'].toString().trim()
        : 'delivery';
    final String nowIso = DateTime.now().toUtc().toIso8601String();
    final String expiresAt =
        (payload['dispatch_offer_expires_at']?.toString().trim().isNotEmpty ??
            false)
        ? payload['dispatch_offer_expires_at'].toString().trim()
        : DateTime.now()
              .toUtc()
              .add(const Duration(seconds: 60))
              .toIso8601String();

    return OrderModel(
      id: orderId,
      orderStatus: AppConstants.pending,
      orderType: orderType,
      createdAt: nowIso,
      updatedAt: nowIso,
      storeName: title,
      storeAddress: title,
      storeLat: '0',
      storeLng: '0',
      deliveryCharge: 0,
      originalDeliveryCharge: 0,
      dmTips: 0,
      dispatchOfferActive: true,
      dispatchOfferExpiresAt: expiresAt,
      dispatchOfferSource: 'push_fallback',
      deliveryAddress: DeliveryAddress(
        address: description,
        latitude: '0',
        longitude: '0',
      ),
      receiverDetails: DeliveryAddress(
        address: title,
        latitude: '0',
        longitude: '0',
      ),
    );
  }

  void removeFromIgnoreList() {
    List<IgnoreModel> tempList = orderServiceInterface.tempList(
      Get.find<SplashController>().currentTime,
      _ignoredRequests,
    );
    _ignoredRequests = [];
    _ignoredRequests.addAll(tempList);
    orderServiceInterface.setIgnoreList(_ignoredRequests);
  }

  void setOtp(String otp) {
    _otp = otp;
    if (otp != '') {
      update();
    }
  }

  Future<void> getParcelCancellationReasons({
    required bool isBeforePickup,
  }) async {
    _parcelCancellationReasons = null;
    ParcelCancellationReasonsModel? parcelCancellationReasons =
        await orderServiceInterface.getParcelCancellationReasons(
          isBeforePickup: isBeforePickup,
        );
    if (parcelCancellationReasons != null) {
      _parcelCancellationReasons = [];
      _parcelCancellationReasons!.addAll(parcelCancellationReasons.data!);
    }
    update();
  }

  void toggleParcelCancelReason(String reason, bool isSelected) {
    if (isSelected) {
      if (!_selectedParcelCancelReason.contains(reason)) {
        _selectedParcelCancelReason.add(reason);
      }
    } else {
      _selectedParcelCancelReason.remove(reason);
    }
    update();
  }

  bool isReasonSelected(String reason) {
    return _selectedParcelCancelReason.contains(reason);
  }

  void clearSelectedParcelCancelReason() {
    _selectedParcelCancelReason.clear();
  }

  String get selectedTimeFormatted {
    return '${_selectedHour.toString().padLeft(2, '0')}:${_selectedMinute.toString().padLeft(2, '0')} $_selectedPeriod';
  }

  DateTime? get selectedDateTime {
    if (_selectedDate == null) return null;

    int hour24 = _selectedHour;
    if (_selectedPeriod == 'PM' && _selectedHour != 12) {
      hour24 += 12;
    } else if (_selectedPeriod == 'AM' && _selectedHour == 12) {
      hour24 = 0;
    }

    return DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      hour24,
      _selectedMinute,
    );
  }

  void initializeDates(String canceledDateTimeString, int returnDays) {
    try {
      // Parse canceled datetime
      DateTime canceledDateTime = DateTime.parse(canceledDateTimeString);

      // Generate available dates (from canceled date to canceled date + returnDays)
      _availableDates.clear();
      DateTime currentDate = DateTime.now();

      for (int i = 0; i <= returnDays; i++) {
        DateTime availableDate = DateTime(
          canceledDateTime.year,
          canceledDateTime.month,
          canceledDateTime.day + i,
        );

        // Only add dates that are today or in the future
        if (availableDate.isAfter(
              currentDate.subtract(const Duration(days: 1)),
            ) ||
            _isSameDay(availableDate, currentDate)) {
          _availableDates.add(availableDate);
        }
      }

      // Set default selected date to the first available date
      if (_availableDates.isNotEmpty) {
        _selectedDate = _availableDates.first;
      }

      update();
    } catch (e) {
      debugPrint('Error parsing canceled datetime: $e');
    }
  }

  void selectDate(DateTime date) {
    if (_availableDates.contains(date)) {
      _selectedDate = date;
      update();
    }
  }

  void selectHour(int hour) {
    if (hour >= 1 && hour <= 12) {
      _selectedHour = hour;
      update();
    }
  }

  void selectMinute(int minute) {
    if (minute >= 0 && minute <= 59) {
      _selectedMinute = minute;
      update();
    }
  }

  void selectPeriod(String period) {
    if (period == 'AM' || period == 'PM') {
      _selectedPeriod = period;
      update();
    }
  }

  bool isDateSelected(DateTime date) {
    return _selectedDate != null && _isSameDay(_selectedDate!, date);
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  String formatDate(DateTime date) {
    return DateFormat('MMM dd').format(date);
  }

  String formatDateWithDay(DateTime date) {
    return DateFormat('EEE, MMM dd').format(date);
  }

  bool canSubmit() {
    return _selectedDate != null;
  }

  void reset() {
    _selectedDate = null;
    _selectedHour = 11;
    _selectedMinute = 59;
    _selectedPeriod = 'PM';
    _availableDates.clear();
    update();
  }

  Future<void> addParcelReturnDate({
    required int orderId,
    required String returnDate,
  }) async {
    _isLoading = true;
    update();

    await orderServiceInterface.addParcelReturnDate(
      orderId: orderId,
      returnDate: returnDate,
    );
    getOrderWithId(orderId);

    _isLoading = false;
    update();
  }

  Future<void> submitParcelReturn({required int orderId}) async {
    _isLoading = true;
    update();

    bool isSuccess = await orderServiceInterface.submitParcelReturn(
      orderId: orderId,
      orderStatus: 'returned',
      returnOtp: int.parse(_otp),
    );
    if (isSuccess) {
      getOrderWithId(orderId);

      if (Get.isDialogOpen!) {
        Get.back();
      }
      showCustomSnackBar('parcel_returned_successfully'.tr, isError: false);
    }

    _isLoading = false;
    update();
  }

  List<OrderCountModel> get filteredOrderCountList {
    if (_currentOrderCountList == null) return [];
    return _currentOrderCountList!
        .where((status) => (status.count ?? 0) > 0)
        .toList();
  }

  List<OrderCountModel> get filteredHistoryOrderCountList {
    if (_historyOrderCountList == null) return [];
    return _historyOrderCountList!
        .where((status) => (status.count ?? 0) > 0)
        .toList();
  }

  Future<void> getOrderCount(String type) async {
    _isLoading = true;
    _orderType = type;
    List<OrderCountModel>? response = await orderServiceInterface.getOrderCount(
      type,
    );
    if (response != null && response.isNotEmpty) {
      if (_orderType == 'current') {
        _currentOrderCountList = response;
      } else if (_orderType == 'history') {
        _historyOrderCountList = response;
      }
    } else {
      if (_orderType == 'current') {
        _currentOrderCountList = [];
      } else if (_orderType == 'history') {
        _historyOrderCountList = [];
      }
    }
    _isLoading = false;
  }

  void setHistoryOrderStatus(String status) {
    _selectedHistoryStatus = status;
    update();
    getCompletedOrders(1, status: status);
  }

  void setRunningOrderStatus(String status) {
    _selectedRunningStatus = status;
    update();
    getRunningOrders(1, status: status);
  }
}

class GeofenceValidationResult {
  final bool allowed;
  final double distanceMeters;
  final double allowedRadiusMeters;

  const GeofenceValidationResult({
    required this.allowed,
    required this.distanceMeters,
    required this.allowedRadiusMeters,
  });

  double get remainingMeters => max(distanceMeters - allowedRadiusMeters, 0);
}

class OperationalDestination {
  final double latitude;
  final double longitude;

  const OperationalDestination({
    required this.latitude,
    required this.longitude,
  });

  bool get isValid {
    final bool latitudeIsValid = latitude >= -90 && latitude <= 90;
    final bool longitudeIsValid = longitude >= -180 && longitude <= 180;
    return latitudeIsValid &&
        longitudeIsValid &&
        !(latitude == 0 && longitude == 0);
  }
}

class OperationalLocationException implements Exception {
  final String message;

  const OperationalLocationException(this.message);
}
