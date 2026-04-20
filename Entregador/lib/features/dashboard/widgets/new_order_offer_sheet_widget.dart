import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:fox_delivery_driver/features/address/controllers/address_controller.dart';
import 'package:fox_delivery_driver/features/order/controllers/order_controller.dart';
import 'package:fox_delivery_driver/features/order/domain/models/order_model.dart';
import 'package:fox_delivery_driver/features/profile/controllers/profile_controller.dart';
import 'package:fox_delivery_driver/features/splash/controllers/splash_controller.dart';
import 'package:fox_delivery_driver/helper/price_converter_helper.dart';
import 'package:fox_delivery_driver/helper/route_helper.dart';
import 'package:fox_delivery_driver/util/styles.dart';

class NewOrderOfferSheetWidget extends StatefulWidget {
  final OrderModel orderModel;
  const NewOrderOfferSheetWidget({super.key, required this.orderModel});

  @override
  State<NewOrderOfferSheetWidget> createState() =>
      _NewOrderOfferSheetWidgetState();
}

class _NewOrderOfferSheetWidgetState extends State<NewOrderOfferSheetWidget> {
  static const int _offerWindowInSeconds = 60;
  Timer? _countDownTimer;
  Timer? _alarmTimer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = _resolveRemainingSeconds();
    _playAlarm();

    _countDownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds <= 1) {
        timer.cancel();
        _reject(expired: true);
      } else {
        setState(() {
          _remainingSeconds -= 1;
        });
      }
    });
  }

  @override
  void dispose() {
    _countDownTimer?.cancel();
    _alarmTimer?.cancel();
    super.dispose();
  }

  int _resolveRemainingSeconds() {
    if (widget.orderModel.dispatchOfferExpiresAt != null) {
      final DateTime? expiresAt = DateTime.tryParse(
        widget.orderModel.dispatchOfferExpiresAt!,
      );
      if (expiresAt != null) {
        return math.max(
          1,
          expiresAt.toLocal().difference(DateTime.now()).inSeconds,
        );
      }
    }
    if (widget.orderModel.createdAt == null) {
      return _offerWindowInSeconds;
    }
    final DateTime? createdAt = DateTime.tryParse(widget.orderModel.createdAt!);
    if (createdAt == null) {
      return _offerWindowInSeconds;
    }
    final int elapsed = DateTime.now()
        .difference(createdAt.toLocal())
        .inSeconds;
    return math.max(1, _offerWindowInSeconds - elapsed);
  }

  void _playAlarm() {
    final player = AudioPlayer();
    player.play(AssetSource('notification.mp3'));
    _alarmTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      player.play(AssetSource('notification.mp3'));
    });
  }

  double _distanceKm() {
    final bool parcel = widget.orderModel.orderType == 'parcel';
    final pickupLat =
        double.tryParse(
          parcel
              ? widget.orderModel.receiverDetails?.latitude ?? '0'
              : widget.orderModel.storeLat ?? '0',
        ) ??
        0;
    final pickupLng =
        double.tryParse(
          parcel
              ? widget.orderModel.receiverDetails?.longitude ?? '0'
              : widget.orderModel.storeLng ?? '0',
        ) ??
        0;
    final dropLat =
        double.tryParse(widget.orderModel.deliveryAddress?.latitude ?? '0') ??
        0;
    final dropLng =
        double.tryParse(widget.orderModel.deliveryAddress?.longitude ?? '0') ??
        0;

    final location = Get.find<ProfileController>().recordLocationBody;
    final fromDriverMeters = Geolocator.distanceBetween(
      location?.latitude ?? pickupLat,
      location?.longitude ?? pickupLng,
      pickupLat,
      pickupLng,
    );
    final routeMeters = Geolocator.distanceBetween(
      pickupLat,
      pickupLng,
      dropLat,
      dropLng,
    );

    return (fromDriverMeters + routeMeters) / 1000;
  }

  String _etaFromDistance(double km) {
    final int mins = math.max(5, (km / 0.45).round());
    return '$mins min';
  }

  String _resolveRouteTypeLabel(bool isParcel) {
    final String? orderType = widget.orderModel.orderType?.toLowerCase();
    if (orderType == 'parcel' || isParcel) {
      return 'Rota para Entrega';
    }
    return 'Rota para Moto';
  }

  Future<void> _reject({bool expired = false}) async {
    final orderController = Get.find<OrderController>();
    final int liveIndex =
        orderController.latestOrderList?.indexWhere(
          (element) => element.id == widget.orderModel.id,
        ) ??
        -1;
    if (liveIndex >= 0) {
      await orderController.rejectOrder(liveIndex, expired: expired);
    }
    orderController.setIncomingOfferOrder(null);
    _countDownTimer?.cancel();
    _alarmTimer?.cancel();
    if (Get.isDialogOpen == true) {
      Get.back();
    }
    if (expired) {
      Get.snackbar(
        'Oferta expirada',
        'A corrida n\u00e3o est\u00e1 mais dispon\u00edvel.',
      );
    }
  }

  Future<void> _accept() async {
    final orderController = Get.find<OrderController>();
    final int liveIndex =
        orderController.latestOrderList?.indexWhere(
          (element) => element.id == widget.orderModel.id,
        ) ??
        -1;
    if (liveIndex < 0) {
      await _reject();
      return;
    }
    final bool isSuccess = await orderController.acceptOrder(
      widget.orderModel.id,
      liveIndex,
      widget.orderModel,
      closeDialog: false,
    );
    if (!mounted) {
      return;
    }
    if (isSuccess) {
      orderController.setIncomingOfferOrder(null);
      widget.orderModel.orderStatus =
          (widget.orderModel.orderStatus == 'pending' ||
              widget.orderModel.orderStatus == 'confirmed')
          ? 'accepted'
          : widget.orderModel.orderStatus;
      orderController.initializeOperationalFlow(widget.orderModel);
      if (Get.isDialogOpen == true) {
        Get.back();
      }
      Get.toNamed(RouteHelper.getDeliveryOperationRoute(widget.orderModel.id!));
    } else {
      await orderController.getLatestOrders();
      await _reject();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool parcel = widget.orderModel.orderType == 'parcel';
    final bool showEarning =
        Get.find<SplashController>().configModel!.showDmEarning! &&
        Get.find<ProfileController>().profileModel != null &&
        Get.find<ProfileController>().profileModel!.earnings == 1;

    final double distanceKm = _distanceKm();
    final int distanceFromDriver = Get.find<AddressController>()
        .getRestaurantDistance(
          LatLng(
            double.parse(
              parcel
                  ? widget.orderModel.deliveryAddress?.latitude ?? '0'
                  : widget.orderModel.storeLat ?? '0',
            ),
            double.parse(
              parcel
                  ? widget.orderModel.deliveryAddress?.longitude ?? '0'
                  : widget.orderModel.storeLng ?? '0',
            ),
          ),
        )
        .round();

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 14,
              right: 14,
              bottom: 360,
              child: _RouteTagsCard(orderModel: widget.orderModel),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 24,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 98,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8E8EB),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F2F5),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            showEarning
                                ? PriceConverterHelper.convertPrice(
                                    (widget.orderModel.originalDeliveryCharge ??
                                            0) +
                                        (widget.orderModel.dmTips ?? 0),
                                  )
                                : 'Corrida #${widget.orderModel.id}',
                            style: robotoBold.copyWith(
                              fontSize: 56,
                              color: const Color(0xFF25262B),
                              height: 0.95,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _resolveRouteTypeLabel(parcel),
                            style: robotoMedium.copyWith(
                              fontSize: 18,
                              color: const Color(0xFF1B8F4A),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1, color: Color(0xFFD9D9DD)),
                          const SizedBox(height: 10),
                          _SummaryRow(
                            label: 'Dist\u00e2ncia total',
                            value:
                                '${distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km',
                          ),
                          const SizedBox(height: 6),
                          _SummaryRow(
                            label: 'Tempo aproximado de rota',
                            value: _etaFromDistance(distanceKm),
                          ),
                          const SizedBox(height: 10),
                          const Divider(height: 1, color: Color(0xFFD9D9DD)),
                          const SizedBox(height: 10),
                          _SummaryRow(
                            label: 'Possibilidade de devolu\u00e7\u00e3o',
                            value: widget.orderModel.parcelCancellation != null
                                ? 'Sim'
                                : 'N\u00e3o',
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                distanceFromDriver > 1000
                                    ? '1000+ km de voc\u00ea'
                                    : ' km de voc\u00ea',
                                style: robotoMedium.copyWith(
                                  fontSize: 11,
                                  color: const Color(0xFF5D6270),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFE2E2E6)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 64,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFE8003A),
                                    Color(0xFFC8002F),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: TextButton(
                                onPressed: _reject,
                                style: TextButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  foregroundColor: Colors.white,
                                ),
                                child: Text(
                                  'Rejeitar',
                                  style: robotoBold.copyWith(
                                    color: Colors.white,
                                    fontSize: 24,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 64,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF228848),
                                    Color(0xFF0D7A3B),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: ElevatedButton(
                                onPressed: _accept,
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  backgroundColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Aceitar',
                                      style: robotoBold.copyWith(
                                        color: Colors.white,
                                        fontSize: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    _CountdownBadge(seconds: _remainingSeconds),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: robotoRegular.copyWith(
              fontSize: 18,
              color: const Color(0xFF5D6270),
            ),
          ),
        ),
        Text(
          value,
          style: robotoBold.copyWith(
            fontSize: 18,
            color: const Color(0xFF2C2F38),
          ),
        ),
      ],
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  final int seconds;
  const _CountdownBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.7),
          width: 4,
        ),
      ),
      child: Text(
        '$seconds',
        style: robotoBold.copyWith(color: Colors.white, fontSize: 20),
      ),
    );
  }
}

class _RouteTagsCard extends StatelessWidget {
  final OrderModel orderModel;
  const _RouteTagsCard({required this.orderModel});

  @override
  Widget build(BuildContext context) {
    final String pickupName = orderModel.storeName?.isNotEmpty == true
        ? orderModel.storeName!
        : 'Coleta';
    final String dropName =
        orderModel.deliveryAddress?.address?.isNotEmpty == true
        ? orderModel.deliveryAddress!.address!
        : orderModel.receiverDetails?.address ?? 'Entrega';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _SmallTag(
              label: 'Coleta 1',
              value: pickupName,
              icon: Icons.store_mall_directory_rounded,
              dotColor: const Color(0xFF2BAA4A),
            ),
            _SmallTag(
              label: 'Entrega 1',
              value: dropName,
              icon: Icons.home_rounded,
              dotColor: const Color(0xFFE14747),
            ),
          ],
        ),
      ],
    );
  }
}

class _SmallTag extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color dotColor;
  const _SmallTag({
    required this.label,
    required this.value,
    required this.icon,
    required this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 170, maxWidth: 220),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFF808592)),
              const SizedBox(width: 6),
              Text(
                label,
                style: robotoBold.copyWith(
                  fontSize: 16,
                  color: const Color(0xFF2C2F38),
                ),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: robotoRegular.copyWith(
              fontSize: 14,
              color: const Color(0xFF515664),
            ),
          ),
        ],
      ),
    );
  }
}
