import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:fox_delivery_driver/common/widgets/custom_app_bar_widget.dart';
import 'package:fox_delivery_driver/common/widgets/custom_button_widget.dart';
import 'package:fox_delivery_driver/common/widgets/custom_snackbar_widget.dart';
import 'package:fox_delivery_driver/features/order/controllers/order_controller.dart';
import 'package:fox_delivery_driver/features/order/domain/models/delivery_operation_stage.dart';
import 'package:fox_delivery_driver/features/order/domain/models/order_details_model.dart';
import 'package:fox_delivery_driver/features/order/domain/models/order_model.dart';
import 'package:fox_delivery_driver/features/profile/controllers/profile_controller.dart';
import 'package:fox_delivery_driver/features/splash/controllers/splash_controller.dart';
import 'package:fox_delivery_driver/helper/route_helper.dart';
import 'package:fox_delivery_driver/util/app_constants.dart';
import 'package:fox_delivery_driver/util/dimensions.dart';
import 'package:fox_delivery_driver/util/styles.dart';
import 'package:url_launcher/url_launcher.dart';

class DeliveryOperationScreen extends StatefulWidget {
  final int orderId;
  const DeliveryOperationScreen({super.key, required this.orderId});

  @override
  State<DeliveryOperationScreen> createState() => _DeliveryOperationScreenState();
}

class _DeliveryOperationScreenState extends State<DeliveryOperationScreen> {
  final TextEditingController _deliveryCodeController = TextEditingController();
  Timer? _refreshTimer;
  DeliveryOperationStage? _scheduledStage;

  @override
  void initState() {
    super.initState();
    _loadOrder();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadOrder());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _deliveryCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    final OrderController orderController = Get.find<OrderController>();
    orderController.syncDeliveryGeofenceRadiusFromConfig(Get.find<SplashController>().configModel, shouldUpdate: false);
    await orderController.getOrderWithId(widget.orderId, popScreenOnError: false);

    final OrderModel? order = orderController.orderModel;
    if (order == null) {
      if (mounted) {
        Get.offAllNamed(RouteHelper.getInitialRoute());
      }
      return;
    }

    await orderController.getOrderDetails(order.id, order.orderType == 'parcel');
    await orderController.initializeOperationalFlow(order, shouldUpdate: false);
    orderController.update();
  }

  Future<void> _openExternalNavigation({
    required double latitude,
    required double longitude,
  }) async {
    final Uri navigationUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude&travelmode=driving',
    );

    final bool didLaunch = await launchUrl(navigationUri, mode: LaunchMode.externalApplication);
    if (!didLaunch) {
      showCustomSnackBar('Nao foi possivel abrir a navegacao externa agora.');
    }
  }

  void _scheduleAutoTransition({
    required DeliveryOperationStage stage,
    required OrderController orderController,
    required OrderModel order,
  }) {
    if (_scheduledStage == stage) {
      return;
    }

    Duration? delay;
    DeliveryOperationStage? nextStage;

    if (stage == DeliveryOperationStage.arrivedAtStore) {
      delay = const Duration(milliseconds: 900);
      nextStage = DeliveryOperationStage.waitingStoreReady;
    } else if (stage == DeliveryOperationStage.pickupConfirmed) {
      delay = const Duration(milliseconds: 900);
      nextStage = DeliveryOperationStage.onTheWayToCustomer;
    } else if (stage == DeliveryOperationStage.arrivedAtCustomer) {
      delay = const Duration(milliseconds: 900);
      nextStage = DeliveryOperationStage.awaitingDeliveryCode;
    } else if (stage == DeliveryOperationStage.deliveryCompleted) {
      delay = const Duration(milliseconds: 1500);
    }

    if (delay == null) {
      _scheduledStage = null;
      return;
    }

    _scheduledStage = stage;
    Future.delayed(delay, () async {
      if (!mounted) {
        return;
      }

      if (stage == DeliveryOperationStage.deliveryCompleted) {
        await orderController.clearOperationalStage(order.id!, shouldUpdate: false);
        if (mounted) {
          Get.offAllNamed(RouteHelper.getInitialRoute());
        }
        return;
      }

      if (nextStage != null) {
        await orderController.setOperationalStage(order.id!, nextStage, shouldUpdate: false);
        orderController.update();
      }
      _scheduledStage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<OrderController>(builder: (orderController) {
      final OrderModel? order = orderController.orderModel;
      if (order == null) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }

      final DeliveryOperationStage stage = orderController.getOperationalStageForOrder(order);
      _scheduleAutoTransition(stage: stage, orderController: orderController, order: order);

      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: CustomAppBarWidget(
          title: 'Pedido #${order.id}',
          actionWidget: const _SupportActionButton(),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadOrder,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OperationalStatusCard(
                    title: orderController.getOperationalStatusLabel(stage),
                    subtitle: _subtitleForStage(stage, order),
                    orderId: order.id ?? 0,
                  ),
                  const SizedBox(height: Dimensions.paddingSizeDefault),
                  _buildStageContent(context, orderController, order, stage),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  String? _subtitleForStage(DeliveryOperationStage stage, OrderModel order) {
    switch (stage) {
      case DeliveryOperationStage.onTheWayToStore:
        return 'Siga atÃ© a loja para continuar o fluxo.';
      case DeliveryOperationStage.arrivedAtStore:
        return 'Chegada registrada. Preparando prÃ³xima etapa.';
      case DeliveryOperationStage.waitingStoreReady:
        return order.orderStatus == AppConstants.handover
            ? 'Pedido pronto para retirada.'
            : 'Aguardando o restaurante liberar a coleta.';
      case DeliveryOperationStage.pickupConfirmation:
        return 'Confira os dados antes de confirmar a retirada.';
      case DeliveryOperationStage.pickupConfirmed:
        return 'Retirada registrada com sucesso.';
      case DeliveryOperationStage.onTheWayToCustomer:
        return 'Siga atÃ© o cliente para finalizar a entrega.';
      case DeliveryOperationStage.arrivedAtCustomer:
        return 'Chegada registrada. Preparando confirmaÃ§Ã£o final.';
      case DeliveryOperationStage.awaitingDeliveryCode:
        return 'Digite o cÃ³digo informado pelo cliente.';
      case DeliveryOperationStage.deliveryCompleted:
        return 'Entrega validada com sucesso.';
      default:
        return null;
    }
  }

  Widget _buildStageContent(
    BuildContext context,
    OrderController orderController,
    OrderModel order,
    DeliveryOperationStage stage,
  ) {
    switch (stage) {
      case DeliveryOperationStage.onTheWayToStore:
        return _buildRouteStage(
          context: context,
          orderController: orderController,
          order: order,
          useStoreDestination: true,
          destinationName: order.storeName ?? 'Loja',
          destinationAddress: order.storeAddress ?? 'EndereÃ§o da loja indisponÃ­vel',
          destinationLatitude: double.tryParse(order.storeLat ?? '') ?? 0,
          destinationLongitude: double.tryParse(order.storeLng ?? '') ?? 0,
          stageTitle: 'A caminho da loja',
          buttonText: 'Cheguei na loja',
          helperText: 'DisponÃ­vel ao chegar a atÃ© ${orderController.deliveryGeofenceRadiusInMeters.round()}m do destino.',
          onPressed: () async {
            await orderController.confirmArrivalAtStore(order);
          },
        );
      case DeliveryOperationStage.arrivedAtStore:
        return _CheckpointStageCard(
          title: 'Cheguei na loja',
          description: 'Chegada confirmada. Aguarde a liberaÃ§Ã£o do pedido para seguir.',
          icon: Icons.store_mall_directory_rounded,
        );
      case DeliveryOperationStage.waitingStoreReady:
        return _buildWaitingStoreReadyStage(orderController, order);
      case DeliveryOperationStage.pickupConfirmation:
        return _buildPickupConfirmationStage(orderController, order);
      case DeliveryOperationStage.pickupConfirmed:
        return _CheckpointStageCard(
          title: 'Retirada confirmada',
          description: 'Coleta concluÃ­da. Preparando rota para o cliente.',
          icon: Icons.shopping_bag_rounded,
        );
      case DeliveryOperationStage.onTheWayToCustomer:
        return _buildRouteStage(
          context: context,
          orderController: orderController,
          order: order,
          useStoreDestination: false,
          destinationName: _customerName(order),
          destinationAddress: _customerAddress(order),
          destinationLatitude: _customerLatitude(order),
          destinationLongitude: _customerLongitude(order),
          stageTitle: 'A caminho do cliente',
          buttonText: 'Cheguei no cliente',
          helperText: 'DisponÃ­vel ao chegar a atÃ© ${orderController.deliveryGeofenceRadiusInMeters.round()}m do destino.',
          onPressed: () async {
            await orderController.confirmArrivalAtCustomer(order);
          },
        );
      case DeliveryOperationStage.arrivedAtCustomer:
        return _CheckpointStageCard(
          title: 'Cheguei no cliente',
          description: 'Chegada confirmada. Agora confirme a entrega com o cÃ³digo do cliente.',
          icon: Icons.person_pin_circle_rounded,
        );
      case DeliveryOperationStage.awaitingDeliveryCode:
        return _buildDeliveryCodeStage(orderController, order);
      case DeliveryOperationStage.deliveryCompleted:
        return _CheckpointStageCard(
          title: 'Entrega concluÃ­da',
          description: 'Finalizando o atendimento e retornando para a home.',
          icon: Icons.check_circle_rounded,
          isSuccess: true,
        );
      default:
        return const SizedBox();
    }
  }

  Widget _buildRouteStage({
    required BuildContext context,
    required OrderController orderController,
    required OrderModel order,
    required bool useStoreDestination,
    required String destinationName,
    required String destinationAddress,
    required double destinationLatitude,
    required double destinationLongitude,
    required String stageTitle,
    required String buttonText,
    required String helperText,
    required Future<void> Function() onPressed,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OperationalSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(stageTitle, style: robotoBold.copyWith(fontSize: Dimensions.fontSizeLarge)),
              const SizedBox(height: Dimensions.paddingSizeSmall),
              Text(destinationName, style: robotoMedium.copyWith(fontSize: Dimensions.fontSizeDefault)),
              const SizedBox(height: Dimensions.paddingSizeExtraSmall),
              Text(destinationAddress, style: robotoRegular.copyWith(color: Theme.of(context).hintColor)),
              const SizedBox(height: Dimensions.paddingSizeDefault),
              _RouteMetricsRow(
                orderController: orderController,
                order: order,
                useStoreDestination: useStoreDestination,
              ),
              const SizedBox(height: Dimensions.paddingSizeDefault),
              ClipRRect(
                borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
                child: SizedBox(
                  height: 280,
                  child: _OperationalRouteMap(
                    destinationName: destinationName,
                    destinationAddress: destinationAddress,
                    destinationLatitude: destinationLatitude,
                    destinationLongitude: destinationLongitude,
                  ),
                ),
              ),
              const SizedBox(height: Dimensions.paddingSizeDefault),
              OutlinedButton.icon(
                onPressed: () async => _openExternalNavigation(
                  latitude: destinationLatitude,
                  longitude: destinationLongitude,
                ),
                icon: const Icon(Icons.navigation_rounded),
                label: const Text('Abrir navegacao'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.25)),
                  foregroundColor: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: Dimensions.paddingSizeDefault),
              CustomButtonWidget(
                buttonText: buttonText,
                onPressed: () async => await onPressed(),
              ),
              const SizedBox(height: Dimensions.paddingSizeSmall),
              Text(
                helperText,
                style: robotoRegular.copyWith(
                  color: Theme.of(context).hintColor,
                  fontSize: Dimensions.fontSizeSmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingStoreReadyStage(OrderController orderController, OrderModel order) {
    final bool canPickup = order.orderStatus == AppConstants.handover;
    return _OperationalSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Aguardando pedido pronto', style: robotoBold.copyWith(fontSize: Dimensions.fontSizeLarge)),
          const SizedBox(height: Dimensions.paddingSizeDefault),
          _InfoRow(label: 'NÃºmero do pedido', value: '#${order.id}'),
          const SizedBox(height: Dimensions.paddingSizeSmall),
          _InfoRow(label: 'EndereÃ§o da loja', value: order.storeAddress ?? 'EndereÃ§o indisponÃ­vel'),
          const SizedBox(height: Dimensions.paddingSizeSmall),
          _InfoRow(
            label: 'Status atual',
            value: canPickup ? 'Pedido pronto para retirada' : 'Aguardando pedido pronto',
          ),
          if (canPickup) ...[
            const SizedBox(height: Dimensions.paddingSizeLarge),
            CustomButtonWidget(
              buttonText: 'Retirar pedido',
              onPressed: () async {
                await orderController.startPickupConfirmation(order);
              },
            ),
            const SizedBox(height: Dimensions.paddingSizeSmall),
            Text(
              'DisponÃ­vel ao chegar a atÃ© ${orderController.deliveryGeofenceRadiusInMeters.round()}m da loja.',
              style: robotoRegular.copyWith(color: Get.theme.hintColor, fontSize: Dimensions.fontSizeSmall),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPickupConfirmationStage(OrderController orderController, OrderModel order) {
    final List<OrderDetailsModel> details = orderController.orderDetailsModel ?? [];
    return _OperationalSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ConfirmaÃ§Ã£o de coleta', style: robotoBold.copyWith(fontSize: Dimensions.fontSizeLarge)),
          const SizedBox(height: Dimensions.paddingSizeDefault),
          _InfoRow(label: 'Cliente', value: _customerName(order)),
          const SizedBox(height: Dimensions.paddingSizeSmall),
          _InfoRow(label: 'CÃ³digo de coleta', value: orderController.getPickupReference(order)),
          const SizedBox(height: Dimensions.paddingSizeSmall),
          Text('Resumo do pedido', style: robotoMedium.copyWith(fontSize: Dimensions.fontSizeDefault)),
          const SizedBox(height: Dimensions.paddingSizeSmall),
          if (details.isEmpty)
            Text(
              'Resumo indisponÃ­vel no momento.',
              style: robotoRegular.copyWith(color: Get.theme.hintColor),
            )
          else
            ...details.take(5).map((detail) {
              final String itemName = detail.itemDetails?.name ?? 'Item';
              final String quantity = (detail.quantity ?? 1).toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: Dimensions.paddingSizeExtraSmall),
                child: Row(
                  children: [
                    Expanded(child: Text(itemName, style: robotoRegular)),
                    Text('x$quantity', style: robotoMedium),
                  ],
                ),
              );
            }),
          const SizedBox(height: Dimensions.paddingSizeLarge),
          CustomButtonWidget(
            buttonText: 'Confirmar retirada',
            isLoading: orderController.isLoading,
            onPressed: () async {
              await orderController.confirmPickup(order);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryCodeStage(OrderController orderController, OrderModel order) {
    return _OperationalSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Aguardando cÃ³digo de entrega', style: robotoBold.copyWith(fontSize: Dimensions.fontSizeLarge)),
          const SizedBox(height: Dimensions.paddingSizeDefault),
          _InfoRow(label: 'Cliente', value: _customerName(order)),
          const SizedBox(height: Dimensions.paddingSizeLarge),
          Text('CÃ³digo do cliente', style: robotoMedium.copyWith(fontSize: Dimensions.fontSizeDefault)),
          const SizedBox(height: Dimensions.paddingSizeSmall),
          TextField(
            controller: _deliveryCodeController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(
              hintText: 'Digite o cÃ³digo de 4 nÃºmeros',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
                borderSide: BorderSide(color: Theme.of(context).primaryColor),
              ),
            ),
          ),
          const SizedBox(height: Dimensions.paddingSizeLarge),
          CustomButtonWidget(
            buttonText: 'Confirmar entrega',
            isLoading: orderController.isLoading,
            onPressed: () async {
              await orderController.confirmDeliveryWithCode(order, _deliveryCodeController.text);
            },
          ),
          const SizedBox(height: Dimensions.paddingSizeSmall),
          Text(
            'A entrega sÃ³ serÃ¡ concluÃ­da dentro da geofence do cliente e com cÃ³digo vÃ¡lido.',
            style: robotoRegular.copyWith(color: Theme.of(context).hintColor, fontSize: Dimensions.fontSizeSmall),
          ),
        ],
      ),
    );
  }

  String _customerName(OrderModel order) {
    if (order.orderType == 'parcel' && order.receiverDetails?.contactPersonName != null) {
      return order.receiverDetails!.contactPersonName!;
    }
    return '${order.customer?.fName ?? ''} ${order.customer?.lName ?? ''}'.trim().isEmpty
        ? 'Cliente'
        : '${order.customer?.fName ?? ''} ${order.customer?.lName ?? ''}'.trim();
  }

  String _customerAddress(OrderModel order) {
    if (order.orderType == 'parcel' && order.receiverDetails?.address != null) {
      return order.receiverDetails!.address!;
    }
    return order.deliveryAddress?.address ?? 'EndereÃ§o do cliente indisponÃ­vel';
  }

  double _customerLatitude(OrderModel order) {
    if (order.orderType == 'parcel' && order.receiverDetails?.latitude != null) {
      return double.tryParse(order.receiverDetails!.latitude ?? '') ?? 0;
    }
    return double.tryParse(order.deliveryAddress?.latitude ?? '') ?? 0;
  }

  double _customerLongitude(OrderModel order) {
    if (order.orderType == 'parcel' && order.receiverDetails?.longitude != null) {
      return double.tryParse(order.receiverDetails!.longitude ?? '') ?? 0;
    }
    return double.tryParse(order.deliveryAddress?.longitude ?? '') ?? 0;
  }
}

class _OperationalStatusCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int orderId;

  const _OperationalStatusCard({
    required this.title,
    required this.subtitle,
    required this.orderId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 18)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status atual', style: robotoRegular.copyWith(color: Theme.of(context).hintColor)),
          const SizedBox(height: Dimensions.paddingSizeExtraSmall),
          Text(title, style: robotoBold.copyWith(fontSize: Dimensions.fontSizeOverLarge)),
          if (subtitle != null) ...[
            const SizedBox(height: Dimensions.paddingSizeExtraSmall),
            Text(subtitle!, style: robotoRegular.copyWith(color: Theme.of(context).hintColor)),
          ],
          const SizedBox(height: Dimensions.paddingSizeSmall),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Dimensions.paddingSizeSmall,
              vertical: Dimensions.paddingSizeExtraSmall,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Dimensions.radiusSmall),
            ),
            child: Text('Pedido #$orderId', style: robotoMedium.copyWith(color: Theme.of(context).primaryColor)),
          ),
        ],
      ),
    );
  }
}

class _OperationalSectionCard extends StatelessWidget {
  final Widget child;
  const _OperationalSectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 18)],
      ),
      child: child,
    );
  }
}

class _RouteMetricsRow extends StatelessWidget {
  final OrderController orderController;
  final OrderModel order;
  final bool useStoreDestination;

  const _RouteMetricsRow({
    required this.orderController,
    required this.order,
    required this.useStoreDestination,
  });

  @override
  Widget build(BuildContext context) {
    final double? distance = orderController.getCachedDistanceToDestination(
      order: order,
      useStoreDestination: useStoreDestination,
    );

    return Wrap(
      spacing: Dimensions.paddingSizeSmall,
      runSpacing: Dimensions.paddingSizeSmall,
      children: [
        _MetricChip(
          icon: Icons.route_rounded,
          label: 'Distancia atual',
          value: distance == null ? 'Atualizando' : orderController.formatOperationalDistance(distance),
        ),
        _MetricChip(
          icon: Icons.my_location_rounded,
          label: 'Geofence',
          value: '${orderController.deliveryGeofenceRadiusInMeters.round()} m',
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimensions.paddingSizeSmall,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Dimensions.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).primaryColor),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: robotoMedium.copyWith(
              color: Theme.of(context).primaryColor,
              fontSize: Dimensions.fontSizeSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: robotoRegular.copyWith(color: Theme.of(context).hintColor)),
        const SizedBox(height: 4),
        Text(value, style: robotoMedium),
      ],
    );
  }
}

class _CheckpointStageCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool isSuccess;

  const _CheckpointStageCard({
    required this.title,
    required this.description,
    required this.icon,
    this.isSuccess = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color accentColor = isSuccess ? Colors.green : Theme.of(context).primaryColor;
    return _OperationalSectionCard(
      child: Column(
        children: [
          Container(
            height: 72,
            width: 72,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accentColor, size: 36),
          ),
          const SizedBox(height: Dimensions.paddingSizeDefault),
          Text(title, style: robotoBold.copyWith(fontSize: Dimensions.fontSizeLarge)),
          const SizedBox(height: Dimensions.paddingSizeSmall),
          Text(
            description,
            textAlign: TextAlign.center,
            style: robotoRegular.copyWith(color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }
}

class _SupportActionButton extends StatelessWidget {
  const _SupportActionButton();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Get.toNamed(RouteHelper.getConversationListRoute()),
      borderRadius: BorderRadius.circular(Dimensions.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Dimensions.paddingSizeSmall, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Dimensions.radiusSmall),
          color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
        ),
        child: Row(
          children: [
            Icon(Icons.support_agent_rounded, size: 18, color: Theme.of(context).primaryColor),
            const SizedBox(width: 6),
            Text('Suporte', style: robotoMedium.copyWith(color: Theme.of(context).primaryColor)),
          ],
        ),
      ),
    );
  }
}

class _OperationalRouteMap extends StatefulWidget {
  final String destinationName;
  final String destinationAddress;
  final double destinationLatitude;
  final double destinationLongitude;

  const _OperationalRouteMap({
    required this.destinationName,
    required this.destinationAddress,
    required this.destinationLatitude,
    required this.destinationLongitude,
  });

  @override
  State<_OperationalRouteMap> createState() => _OperationalRouteMapState();
}

class _OperationalRouteMapState extends State<_OperationalRouteMap> {
  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  Timer? _locationRefreshTimer;
  final Set<Marker> _markers = <Marker>{};
  final Set<Polyline> _polylines = <Polyline>{};
  final Set<Circle> _circles = <Circle>{};

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    _locationRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadCurrentLocation());
  }

  @override
  void didUpdateWidget(covariant _OperationalRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destinationLatitude != widget.destinationLatitude
        || oldWidget.destinationLongitude != widget.destinationLongitude) {
      _loadCurrentLocation();
    } else {
      _updateMapObjects();
    }
  }

  @override
  void dispose() {
    _locationRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentLocation() async {
    final recordLocation = Get.find<ProfileController>().recordLocationBody;
    if (recordLocation?.latitude != null && recordLocation?.longitude != null) {
      _currentLocation = LatLng(recordLocation!.latitude!, recordLocation.longitude!);
      _updateMapObjects();
      return;
    }

    try {
      final Position position = await Geolocator.getCurrentPosition();
      _currentLocation = LatLng(position.latitude, position.longitude);
    } catch (_) {
      _currentLocation = null;
    }

    _updateMapObjects();
  }

  void _updateMapObjects() {
    final LatLng destination = LatLng(widget.destinationLatitude, widget.destinationLongitude);
    final Color accentColor = Get.theme.primaryColor;
    _markers
      ..clear()
      ..add(Marker(
        markerId: const MarkerId('destination'),
        position: destination,
        infoWindow: InfoWindow(title: widget.destinationName, snippet: widget.destinationAddress),
      ));

    if (_currentLocation != null) {
      _markers.add(Marker(
        markerId: const MarkerId('delivery_man'),
        position: _currentLocation!,
        infoWindow: const InfoWindow(title: 'Entregador'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ));
    }

    _polylines
      ..clear();
    if (_currentLocation != null) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route_preview'),
          points: <LatLng>[_currentLocation!, destination],
          color: accentColor,
          width: 5,
        ),
      );
    }

    _circles
      ..clear()
      ..add(
        Circle(
          circleId: const CircleId('destination_geofence'),
          center: destination,
          radius: Get.find<OrderController>().deliveryGeofenceRadiusInMeters,
          fillColor: accentColor.withValues(alpha: 0.08),
          strokeColor: accentColor.withValues(alpha: 0.55),
          strokeWidth: 2,
        ),
      );

    if (_mapController != null) {
      _moveCamera(destination);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _moveCamera(LatLng destination) async {
    if (_currentLocation == null) {
      await _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: destination, zoom: 16),
      ));
      return;
    }

    if (_currentLocation!.latitude == destination.latitude
        && _currentLocation!.longitude == destination.longitude) {
      await _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: destination, zoom: 16),
      ));
      return;
    }

    final double latPadding = max(((_currentLocation!.latitude - destination.latitude).abs()) * 0.2, 0.003);
    final double lngPadding = max(((_currentLocation!.longitude - destination.longitude).abs()) * 0.2, 0.003);

    final LatLng southwest = LatLng(
      min(_currentLocation!.latitude, destination.latitude) - latPadding,
      min(_currentLocation!.longitude, destination.longitude) - lngPadding,
    );
    final LatLng northeast = LatLng(
      max(_currentLocation!.latitude, destination.latitude) + latPadding,
      max(_currentLocation!.longitude, destination.longitude) + lngPadding,
    );

    await _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: southwest, northeast: northeast),
        48,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LatLng initialTarget = LatLng(widget.destinationLatitude, widget.destinationLongitude);
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: initialTarget, zoom: 16),
      onMapCreated: (GoogleMapController controller) {
        _mapController = controller;
        _updateMapObjects();
      },
      circles: _circles,
      polylines: _polylines,
      compassEnabled: false,
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      markers: _markers,
    );
  }
}
