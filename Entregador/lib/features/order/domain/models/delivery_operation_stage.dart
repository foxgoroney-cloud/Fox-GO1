enum DeliveryOperationStage {
  idle,
  onTheWayToStore,
  arrivedAtStore,
  waitingStoreReady,
  pickupConfirmation,
  pickupConfirmed,
  onTheWayToCustomer,
  arrivedAtCustomer,
  awaitingDeliveryCode,
  deliveryCompleted,
}

extension DeliveryOperationStageX on DeliveryOperationStage {
  String get key {
    switch (this) {
      case DeliveryOperationStage.idle:
        return 'idle';
      case DeliveryOperationStage.onTheWayToStore:
        return 'on_the_way_to_store';
      case DeliveryOperationStage.arrivedAtStore:
        return 'arrived_at_store';
      case DeliveryOperationStage.waitingStoreReady:
        return 'waiting_store_ready';
      case DeliveryOperationStage.pickupConfirmation:
        return 'pickup_confirmation';
      case DeliveryOperationStage.pickupConfirmed:
        return 'pickup_confirmed';
      case DeliveryOperationStage.onTheWayToCustomer:
        return 'on_the_way_to_customer';
      case DeliveryOperationStage.arrivedAtCustomer:
        return 'arrived_at_customer';
      case DeliveryOperationStage.awaitingDeliveryCode:
        return 'awaiting_delivery_code';
      case DeliveryOperationStage.deliveryCompleted:
        return 'delivery_completed';
    }
  }

  bool get isStoreStage {
    return this == DeliveryOperationStage.onTheWayToStore
        || this == DeliveryOperationStage.arrivedAtStore
        || this == DeliveryOperationStage.waitingStoreReady
        || this == DeliveryOperationStage.pickupConfirmation
        || this == DeliveryOperationStage.pickupConfirmed;
  }
}

DeliveryOperationStage deliveryOperationStageFromKey(String? key) {
  switch (key) {
    case 'on_the_way_to_store':
      return DeliveryOperationStage.onTheWayToStore;
    case 'arrived_at_store':
      return DeliveryOperationStage.arrivedAtStore;
    case 'waiting_store_ready':
      return DeliveryOperationStage.waitingStoreReady;
    case 'pickup_confirmation':
      return DeliveryOperationStage.pickupConfirmation;
    case 'pickup_confirmed':
      return DeliveryOperationStage.pickupConfirmed;
    case 'on_the_way_to_customer':
      return DeliveryOperationStage.onTheWayToCustomer;
    case 'arrived_at_customer':
      return DeliveryOperationStage.arrivedAtCustomer;
    case 'awaiting_delivery_code':
      return DeliveryOperationStage.awaitingDeliveryCode;
    case 'delivery_completed':
      return DeliveryOperationStage.deliveryCompleted;
    default:
      return DeliveryOperationStage.idle;
  }
}
