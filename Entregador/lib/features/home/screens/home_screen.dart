import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fox_delivery_driver/common/widgets/custom_bottom_sheet_widget.dart';
import 'package:fox_delivery_driver/common/widgets/custom_button_widget.dart';
import 'package:fox_delivery_driver/common/widgets/custom_confirmation_bottom_sheet.dart';
import 'package:fox_delivery_driver/common/widgets/custom_snackbar_widget.dart';
import 'package:fox_delivery_driver/features/auth/controllers/auth_controller.dart';
import 'package:fox_delivery_driver/features/home/widgets/location_access_dialog.dart';
import 'package:fox_delivery_driver/features/notification/controllers/notification_controller.dart';
import 'package:fox_delivery_driver/features/order/controllers/order_controller.dart';
import 'package:fox_delivery_driver/features/order/domain/models/order_model.dart';
import 'package:fox_delivery_driver/features/dashboard/widgets/new_order_offer_sheet_widget.dart';
import 'package:fox_delivery_driver/features/profile/controllers/profile_controller.dart';
import 'package:fox_delivery_driver/features/profile/domain/models/profile_model.dart';
import 'package:fox_delivery_driver/helper/route_helper.dart';
import 'package:fox_delivery_driver/helper/custom_print_helper.dart';
import 'package:fox_delivery_driver/helper/device_settings_helper.dart';
import 'package:fox_delivery_driver/util/dimensions.dart';
import 'package:fox_delivery_driver/util/images.dart';
import 'package:fox_delivery_driver/util/styles.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onNavigateToOrders});
  final Function()? onNavigateToOrders;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AppLifecycleListener _listener;
  bool _isNotificationPermissionGranted = true;
  bool _isOverlayPermissionGranted = true;
  bool _isBatteryOptimizationGranted = true;
  bool _showEarnings = true;
  bool _isBottomPanelExpanded = true;
  int? _lastLoggedIncomingOfferId;
  final NumberFormat _brlFormatter = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  static const double _expandedBottomPanelHeight = 360;
  static const double _collapsedBottomPanelHeight = 124;
  static const double _floatingPanelBottomSpacing = 12;

  @override
  void initState() {
    super.initState();

    _checkSystemNotification();

    _listener = AppLifecycleListener(onStateChange: _onStateChanged);

    _loadData();

    Future.delayed(const Duration(milliseconds: 200), () {
      checkPermission();
    });
  }

  Future<void> _loadData() async {
    Get.find<OrderController>().getIgnoreList();
    Get.find<OrderController>().removeFromIgnoreList();
    await Get.find<ProfileController>().getProfile();
    await Get.find<OrderController>().getRunningOrders(1);
    await Get.find<OrderController>().restorePendingIncomingOffer();
    await Get.find<NotificationController>().getNotificationList();
  }

  Future<void> _checkSystemNotification() async {
    if (await Permission.notification.status.isDenied ||
        await Permission.notification.status.isPermanentlyDenied) {
      await Get.find<AuthController>().setNotificationActive(false);
    }
  }

  void _onStateChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkPermission();
      Get.find<OrderController>().syncPendingIncomingOfferWithServer();
    }
  }

  Future<void> checkPermission() async {
    var notificationStatus = await Permission.notification.status;
    var overlayStatus = await Permission.systemAlertWindow.status;
    var batteryStatus = await Permission.ignoreBatteryOptimizations.status;
    final bool notificationGranted =
        !(notificationStatus.isDenied ||
            notificationStatus.isPermanentlyDenied);
    final bool overlayGranted = overlayStatus.isGranted;
    final bool batteryGranted = batteryStatus.isGranted;

    setState(() {
      _isNotificationPermissionGranted = notificationGranted;
      _isOverlayPermissionGranted = overlayGranted;
      _isBatteryOptimizationGranted = batteryGranted;
    });

    if (!notificationGranted) {
      await Get.find<AuthController>().setNotificationActive(false);
    }

    Get.find<ProfileController>().setBackgroundNotificationActive(
      batteryGranted,
    );
  }

  Future<void> requestNotificationPermission() async {
    final PermissionStatus status = await Permission.notification.request();
    if (!status.isGranted) {
      await DeviceSettingsHelper.openNotificationSettings();
    }

    await checkPermission();
  }

  Future<void> requestOverlayPermission() async {
    final PermissionStatus status = await Permission.systemAlertWindow
        .request();
    if (!status.isGranted) {
      await openAppSettings();
    }

    await checkPermission();
  }

  Future<void> requestBatteryOptimization() async {
    final PermissionStatus status =
        await Permission.ignoreBatteryOptimizations.status;

    if (status.isGranted) {
      return;
    }

    await DeviceSettingsHelper.openBatteryOptimizationSettings();
    await checkPermission();
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () async => _loadData(),
        child: GetBuilder<ProfileController>(
          builder: (profileController) {
            return GetBuilder<OrderController>(
              builder: (orderController) {
                final OrderModel? activeOrder =
                    orderController.currentOrderList != null &&
                        orderController.currentOrderList!.isNotEmpty
                    ? orderController.currentOrderList!.first
                    : null;
                final bool isOnline =
                    (profileController.profileModel?.active ?? 0) == 1;
                final int availableRequests =
                    orderController.latestOrderList?.length ?? 0;
                final OrderModel? pendingIncomingOffer =
                    orderController.incomingOfferOrder;
                if (pendingIncomingOffer?.id != _lastLoggedIncomingOfferId) {
                  _lastLoggedIncomingOfferId = pendingIncomingOffer?.id;
                  customPrint(
                    '[PushFlow][Home] incomingOfferOrder mudou -> ${pendingIncomingOffer?.id}',
                  );
                }

                final String operationalStatus = activeOrder != null
                    ? orderController.getOperationalStatusLabel(
                        orderController.getOperationalStageForOrder(
                          activeOrder,
                        ),
                      )
                    : (isOnline ? 'Aguardando pedido' : 'Desconectado');

                final String avisoOperacional = activeOrder != null
                    ? 'Voc\u00ea est\u00e1 com uma rota em andamento.'
                    : (isOnline
                          ? 'Procurando novas rotas para voc\u00ea.'
                          : 'Fora do seu per\u00edodo de entregas.');

                final double permissionBannerOffset = !isOnline
                    ? 0
                    : [
                            !_isNotificationPermissionGranted,
                            !_isOverlayPermissionGranted,
                            !_isBatteryOptimizationGranted,
                          ].where((bool missing) => missing).length *
                          52.0;

                return SizedBox.expand(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (isOnline)
                        _buildOnlineMapBackground(profileController)
                      else
                        _buildOfflineNeutralBackground(),
                      if (isOnline && !_isNotificationPermissionGranted)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: topPadding,
                          child: permissionWarning(
                            message:
                                'As notificacoes estao desativadas. Ative para receber pedidos.',
                            onTap: requestNotificationPermission,
                            closeOnTap: () => setState(
                              () => _isNotificationPermissionGranted = true,
                            ),
                          ),
                        ),
                      if (isOnline && !_isOverlayPermissionGranted)
                        Positioned(
                          left: 0,
                          right: 0,
                          top:
                              topPadding +
                              (_isNotificationPermissionGranted ? 0 : 52),
                          child: permissionWarning(
                            message:
                                'Permita exibicao sobre outros apps para o card de nova entrega aparecer na hora.',
                            onTap: requestOverlayPermission,
                            closeOnTap: () => setState(
                              () => _isOverlayPermissionGranted = true,
                            ),
                          ),
                        ),
                      if (isOnline && !_isBatteryOptimizationGranted)
                        Positioned(
                          left: 0,
                          right: 0,
                          top:
                              topPadding +
                              (_isNotificationPermissionGranted ? 0 : 52) +
                              (_isOverlayPermissionGranted ? 0 : 52),
                          child: permissionWarning(
                            message:
                                'Para melhor desempenho, permita notificacoes em segundo plano.',
                            onTap: requestBatteryOptimization,
                            closeOnTap: () => setState(
                              () => _isBatteryOptimizationGranted = true,
                            ),
                          ),
                        ),
                      if (isOnline)
                        SafeArea(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                              padding: EdgeInsets.only(
                                top: 10 + permissionBannerOffset,
                              ),
                              child: _buildTopOverlayCard(
                                context,
                                profileController,
                                operationalStatus,
                                avisoOperacional,
                                isOnline,
                                activeOrder != null,
                              ),
                            ),
                          ),
                        ),
                      if (isOnline && pendingIncomingOffer != null)
                        Positioned(
                          top: topPadding + 132 + permissionBannerOffset,
                          left: 16,
                          right: 16,
                          child: TweenAnimationBuilder<double>(
                            key: ValueKey(
                              'incoming-offer-${pendingIncomingOffer.id}-${pendingIncomingOffer.updatedAt ?? ''}',
                            ),
                            duration: const Duration(milliseconds: 360),
                            curve: Curves.easeOutCubic,
                            tween: Tween<double>(begin: 1, end: 0),
                            builder: (context, value, child) {
                              return Transform.translate(
                                offset: Offset(0, value * 56),
                                child: Opacity(
                                  opacity: 1 - value,
                                  child: child,
                                ),
                              );
                            },
                            child: _buildIncomingOfferPriorityCard(
                              context,
                              pendingIncomingOffer,
                              orderController,
                            ),
                          ),
                        ),
                      if (isOnline) ...[
                        _buildMapActions(
                          bottomPadding,
                          isCollapsed: !_isBottomPanelExpanded,
                        ),
                        _buildOnlineBottomPanel(
                          context,
                          profileController,
                          activeOrder,
                          availableRequests,
                          orderController,
                          bottomPadding,
                        ),
                      ] else
                        _buildOfflineHomeLayout(
                          context,
                          profileController,
                          operationalStatus,
                          bottomPadding,
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildOnlineMapBackground(ProfileController profileController) {
    final location = profileController.recordLocationBody;
    final LatLng currentPosition = LatLng(
      location?.latitude ?? -23.55052,
      location?.longitude ?? -46.633308,
    );
    final incomingOffer = Get.find<OrderController>().incomingOfferOrder;
    final bool isParcel = incomingOffer?.orderType == 'parcel';
    final double? pickupLat = double.tryParse(
      isParcel
          ? incomingOffer?.receiverDetails?.latitude ?? ''
          : incomingOffer?.storeLat ?? '',
    );
    final double? pickupLng = double.tryParse(
      isParcel
          ? incomingOffer?.receiverDetails?.longitude ?? ''
          : incomingOffer?.storeLng ?? '',
    );
    final double? dropLat = double.tryParse(
      incomingOffer?.deliveryAddress?.latitude ?? '',
    );
    final double? dropLng = double.tryParse(
      incomingOffer?.deliveryAddress?.longitude ?? '',
    );

    final Set<Marker> markers = {
      Marker(
        markerId: const MarkerId('delivery_man_position'),
        position: currentPosition,
        infoWindow: const InfoWindow(title: 'Voc\u00ea est\u00e1 aqui'),
      ),
    };
    if (pickupLat != null && pickupLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('offer_pickup'),
          position: LatLng(pickupLat, pickupLng),
          infoWindow: const InfoWindow(title: 'Coleta 1'),
        ),
      );
    }
    if (dropLat != null && dropLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('offer_dropoff'),
          position: LatLng(dropLat, dropLng),
          infoWindow: const InfoWindow(title: 'Entrega 1'),
        ),
      );
    }
    final Set<Polyline> polylines = {};
    if (pickupLat != null &&
        pickupLng != null &&
        dropLat != null &&
        dropLng != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('offer_route_preview'),
          points: [LatLng(pickupLat, pickupLng), LatLng(dropLat, dropLng)],
          color: const Color(0xFF2BAA4A),
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
    }

    return Positioned.fill(
      child: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: currentPosition,
          zoom: 15.8,
        ),
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        compassEnabled: false,
        mapToolbarEnabled: false,
        markers: markers,
        polylines: polylines,
      ),
    );
  }

  Widget _buildOfflineNeutralBackground() {
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F7FB), Color(0xFFEDEFF4)],
          ),
        ),
      ),
    );
  }

  Widget _buildTopOverlayCard(
    BuildContext context,
    ProfileController profileController,
    String operationalStatus,
    String aviso,
    bool isOnline,
    bool hasActiveOrder,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: _buildTopoOperacional(
              context,
              profileController,
              operationalStatus,
              isOnline,
              hasActiveOrder,
            ),
          ),
          const SizedBox(height: 10),
          _buildAvisoOperacional(context, aviso, isOnline, hasActiveOrder),
        ],
      ),
    );
  }

  Widget _buildOfflineHomeLayout(
    BuildContext context,
    ProfileController profileController,
    String operationalStatus,
    double bottomPadding,
  ) {
    return SafeArea(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 10, 16, 24 + bottomPadding),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: _buildTopoOperacional(
                context,
                profileController,
                operationalStatus,
                false,
                false,
              ),
            ),
            const SizedBox(height: 16),
            _buildOfflineBlocoPrincipal(context),
          ],
        ),
      ),
    );
  }

  Widget _buildMapActions(double bottomPadding, {required bool isCollapsed}) {
    final double panelHeight = isCollapsed
        ? _collapsedBottomPanelHeight
        : _expandedBottomPanelHeight;

    return Positioned(
      right: 16,
      bottom: panelHeight + _floatingPanelBottomSpacing + bottomPadding + 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildFloatingCircleButton(
            icon: Icons.tune_rounded,
            semanticLabel: 'Filtro e prefer\u00eancias',
            onTap: () {},
          ),
          const SizedBox(height: 12),
          _buildFloatingSosButton(onTap: _showEmergencyContactsSheet),
        ],
      ),
    );
  }

  void _showEmergencyContactsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (context) {
        final emergencyContacts = <Map<String, dynamic>>[
          {
            'label': 'Pol\u00edcia',
            'number': '190',
            'icon': Icons.local_police_rounded,
          },
          {
            'label': 'Ambul\u00e2ncia (SAMU)',
            'number': '192',
            'icon': Icons.medical_services_rounded,
          },
          {
            'label': 'Bombeiros',
            'number': '193',
            'icon': Icons.local_fire_department_rounded,
          },
        ];

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            12 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7DAE1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('Emerg\u00eancia', style: robotoBold.copyWith(fontSize: 20)),
              const SizedBox(height: 4),
              Text(
                'Toque em um n\u00famero para ligar imediatamente.',
                style: robotoRegular.copyWith(
                  fontSize: 13,
                  color: const Color(0xFF6C7380),
                ),
              ),
              const SizedBox(height: 12),
              ...emergencyContacts.map(
                (contact) => _buildEmergencyContactTile(
                  label: contact['label'] as String,
                  number: contact['number'] as String,
                  icon: contact['icon'] as IconData,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmergencyContactTile({
    required String label,
    required String number,
    required IconData icon,
  }) {
    return InkWell(
      onTap: () => _callEmergencyNumber(number),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE7EBF2)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFFE5004E), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: robotoMedium.copyWith(
                      fontSize: 14.5,
                      color: const Color(0xFF1B2230),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(number, style: robotoBold.copyWith(fontSize: 16)),
                ],
              ),
            ),
            const Icon(Icons.call_rounded, color: Color(0xFF1CAF68)),
          ],
        ),
      ),
    );
  }

  Future<void> _callEmergencyNumber(String number) async {
    final String phoneUrl = 'tel:$number';
    if (await canLaunchUrlString(phoneUrl)) {
      await launchUrlString(phoneUrl, mode: LaunchMode.externalApplication);
    } else {
      showCustomSnackBar(
        'N\u00e3o foi poss\u00edvel iniciar a chamada para $number.',
      );
    }
  }

  Widget _buildFloatingCircleButton({
    required IconData icon,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFFFDFEFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE7EBF2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.09),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 24,
            color: const Color(0xFF141821),
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingSosButton({required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4F7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFFD0DE)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE5004E).withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFE5004E),
                size: 22,
              ),
              SizedBox(width: 6),
              Text(
                'SOS',
                style: TextStyle(
                  color: Color(0xFFE5004E),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOnlineBottomPanel(
    BuildContext context,
    ProfileController profileController,
    OrderModel? activeOrder,
    int availableRequests,
    OrderController orderController,
    double bottomPadding,
  ) {
    final bool isCollapsed = !_isBottomPanelExpanded;
    final profile = profileController.profileModel;
    final balance = _showEarnings ? _formatBrl(profile?.balance) : 'R\$ ----';

    return Positioned(
      left: 16,
      right: 16,
      bottom: _floatingPanelBottomSpacing + bottomPadding,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              axisAlignment: -1,
              child: child,
            ),
          );
        },
        child: isCollapsed
            ? _buildBottomPanelShell(
                key: const ValueKey('collapsed_bottom_panel_shell'),
                height: _collapsedBottomPanelHeight,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: _buildCollapsedBottomPanel(profile),
              )
            : _buildBottomPanelShell(
                key: const ValueKey('expanded_bottom_panel_shell'),
                height: _expandedBottomPanelHeight,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: _buildExpandedBottomPanel(
                  profile,
                  balance,
                  activeOrder,
                  availableRequests,
                  orderController,
                ),
              ),
      ),
    );
  }

  Widget _buildBottomPanelShell({
    required Key key,
    required double height,
    required EdgeInsets padding,
    required Widget child,
  }) {
    return Container(
      key: key,
      height: height,
      clipBehavior: Clip.antiAlias,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildExpandedBottomPanel(
    ProfileModel? profile,
    String balance,
    OrderModel? activeOrder,
    int availableRequests,
    OrderController orderController,
  ) {
    return SingleChildScrollView(
      key: const ValueKey('expanded_bottom_panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHandle(
            onTap: () => setState(() => _isBottomPanelExpanded = false),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Rotas pra entregar agora',
              style: robotoBold.copyWith(fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),
          _buildRouteCallout(activeOrder, availableRequests, orderController),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'Resumo de hoje',
              style: robotoBold.copyWith(fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Saldo dispon\u00edvel',
            style: robotoRegular.copyWith(
              fontSize: 12,
              color: const Color(0xFF6C7380),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            balance,
            style: robotoBold.copyWith(
              fontSize: 30,
              color: const Color(0xFF141821),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _earningTile(
                'Hoje',
                _showEarnings ? _formatBrl(profile?.todaysEarning) : '----',
              ),
              _earningTile(
                'Semana',
                _showEarnings ? _formatBrl(profile?.thisWeekEarning) : '----',
              ),
              _earningTile(
                'M\u00eas',
                _showEarnings ? _formatBrl(profile?.thisMonthEarning) : '----',
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () => setState(() => _showEarnings = !_showEarnings),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showEarnings
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _showEarnings ? 'Ocultar' : 'Mostrar',
                      style: robotoMedium.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedBottomPanel(ProfileModel? profile) {
    return InkWell(
      key: const ValueKey('collapsed_bottom_panel'),
      onTap: () => setState(() => _isBottomPanelExpanded = true),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 4,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFC7CDD8),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Center(
            child: Text(
              'Rotas pra entregar agora',
              style: robotoBold.copyWith(fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Resumo de hoje',
            style: robotoMedium.copyWith(
              fontSize: 12,
              color: const Color(0xFF6C7380),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _showEarnings ? _formatBrl(profile?.todaysEarning) : '----',
            style: robotoBold.copyWith(fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelHandle({required VoidCallback onTap}) {
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 64,
          height: 7,
          decoration: BoxDecoration(
            color: const Color(0xFFD7DAE1),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }

  Widget _buildRouteCallout(
    OrderModel? activeOrder,
    int availableRequests,
    OrderController orderController,
  ) {
    return GestureDetector(
      onTap: () {
        if (activeOrder != null) {
          orderController.initializeOperationalFlow(activeOrder);
          Get.toNamed(RouteHelper.getDeliveryOperationRoute(activeOrder.id!));
        } else {
          widget.onNavigateToOrders?.call();
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F3F6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                availableRequests > 0
                    ? 'Veja as rotas dispon\u00edveis'
                    : 'Sem rotas no momento',
                style: robotoRegular.copyWith(
                  fontSize: 14,
                  color: const Color(0xFF4A4D56),
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 28,
              color: Color(0xFF676A74),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingOfferPriorityCard(
    BuildContext context,
    OrderModel offerOrder,
    OrderController orderController,
  ) {
    customPrint(
      '[PushFlow][Home] Renderizando card de nova entrega id=${offerOrder.id}',
    );
    final bool isParcel = offerOrder.orderType == 'parcel';
    final String primaryAddress = isParcel
        ? (offerOrder.receiverDetails?.address ?? 'Coleta')
        : (offerOrder.storeAddress ?? offerOrder.storeName ?? 'Loja');
    final String secondaryAddress =
        offerOrder.deliveryAddress?.address ?? 'Destino';

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF14A45C), Color(0xFF0E7F46)],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.notifications_active_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nova chamada de entrega',
                    style: robotoBold.copyWith(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              primaryAddress,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: robotoMedium.copyWith(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              'Destino: $secondaryAddress',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: robotoRegular.copyWith(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: CustomButtonWidget(
                    buttonText: 'Recusar',
                    onPressed: () async {
                      final int index =
                          orderController.latestOrderList?.indexWhere(
                            (element) => element.id == offerOrder.id,
                          ) ??
                          -1;
                      if (index >= 0) {
                        await orderController.rejectOrder(index);
                      } else {
                        await orderController.clearPendingIncomingOffer();
                      }
                    },
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    fontColor: Colors.white,
                    isBorder: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: CustomButtonWidget(
                    buttonText: 'Ver oferta',
                    onPressed: () => _openOfferSheet(context, offerOrder),
                    backgroundColor: Colors.white,
                    fontColor: const Color(0xFF136A3F),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openOfferSheet(BuildContext context, OrderModel offerOrder) {
    showGeneralDialog(
      context: context,
      barrierLabel: 'new-order-offer',
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (_, __, ___) =>
          NewOrderOfferSheetWidget(orderModel: offerOrder),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
  }

  Widget _buildTopoOperacional(
    BuildContext context,
    ProfileController profileController,
    String operationalStatus,
    bool isOnline,
    bool hasActiveOrder,
  ) {
    final name =
        '${profileController.profileModel?.fName ?? ''} ${profileController.profileModel?.lName ?? ''}'
            .trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildProfileAvatar(
          context: context,
          name: name,
          imageUrl: profileController.profileModel?.imageFullUrl,
          onTap: () => Get.toNamed(RouteHelper.getMainRoute('profile')),
          isDark: false,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statusPillTop(
            operationalStatus,
            isOnline,
            hasActiveOrder: hasActiveOrder,
            onTap: () => _toggleOnlineStatus(
              profileController,
              Get.find<OrderController>(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        InkWell(
          onTap: () => Get.toNamed(RouteHelper.getNotificationRoute()),
          borderRadius: BorderRadius.circular(16),
          child: GetBuilder<NotificationController>(
            builder: (notificationController) => Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE9EDF4)),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.notifications_none_rounded,
                      color: Color(0xFF293241),
                      size: 24,
                    ),
                  ),
                ),
                if (notificationController.hasNotification)
                  Positioned(
                    top: 9,
                    right: 10,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: const Color(0xFFC11743),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: Colors.white, width: 1.4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvisoOperacional(
    BuildContext context,
    String aviso,
    bool isOnline,
    bool hasActiveOrder,
  ) {
    final Color backgroundColor = isOnline
        ? const Color(0xFFF2F8F5)
        : const Color(0xFFF5F6F9);
    final Color borderColor = isOnline
        ? const Color(0xFFDCEEE5)
        : const Color(0xFFE2E6EE);
    final Color iconBackground = isOnline
        ? const Color(0xFFE4F4EC)
        : const Color(0xFFECEFF4);
    final Color iconColor = isOnline
        ? const Color(0xFF167A56)
        : const Color(0xFF6F7785);
    final IconData icon = hasActiveOrder
        ? Icons.alt_route_rounded
        : (isOnline ? Icons.radar_rounded : Icons.schedule_rounded);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              aviso,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: robotoMedium.copyWith(
                color: const Color(0xFF222934),
                fontSize: 13.5,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineBlocoPrincipal(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE3E7EF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        'Fique dispon\u00edvel para ver rotas.',
        style: robotoBold.copyWith(
          fontSize: 18,
          color: const Color(0xFF1B2230),
        ),
      ),
    );
  }

  Widget _buildBlocoPrincipal(
    BuildContext context,
    OrderModel? activeOrder,
    int availableRequests,
    OrderController orderController,
  ) {
    final bool hasActiveOrder = activeOrder != null;
    final String titulo = hasActiveOrder
        ? 'Rota para entregar agora'
        : 'Solicita\u00e7\u00f5es dispon\u00edveis';
    final String subtitulo = hasActiveOrder
        ? 'Pedido #${activeOrder.id} em andamento. Continue seu fluxo para finalizar a entrega.'
        : availableRequests > 0
        ? 'Voc\u00ea tem $availableRequests solicita\u00e7\u00e3o(\u00f5es) aguardando a\u00e7\u00e3o.'
        : 'No momento n\u00e3o h\u00e1 solicita\u00e7\u00f5es. Fique dispon\u00edvel para receber novas rotas.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: robotoBold.copyWith(fontSize: 18)),
        const SizedBox(height: 6),
        Text(
          subtitulo,
          style: robotoRegular.copyWith(
            color: const Color(0xFF606877),
            height: 1.32,
          ),
        ),
        const SizedBox(height: 14),
        CustomButtonWidget(
          buttonText: hasActiveOrder ? 'Continuar entrega' : 'Ver pedidos',
          onPressed: () {
            if (hasActiveOrder) {
              orderController.initializeOperationalFlow(activeOrder);
              Get.toNamed(
                RouteHelper.getDeliveryOperationRoute(activeOrder!.id!),
              );
            } else {
              widget.onNavigateToOrders?.call();
            }
          },
        ),
      ],
    );
  }

  Widget _buildProfileAvatar({
    required BuildContext context,
    required String name,
    required String? imageUrl,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark
              ? Colors.white.withValues(alpha: 0.18)
              : const Color(0xFFF4F6FA),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipOval(
          child: (imageUrl ?? '').trim().isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: imageUrl!,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      _buildAvatarFallback(context, name),
                  errorWidget: (context, url, error) =>
                      _buildAvatarFallback(context, name),
                )
              : _buildAvatarFallback(context, name),
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(BuildContext context, String name) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).primaryColor.withValues(alpha: 0.9),
            Theme.of(context).primaryColor,
          ],
        ),
      ),
      child: Text(
        _avatarInitials(name),
        style: robotoBold.copyWith(
          color: Colors.white,
          fontSize: 14.5,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  String _avatarInitials(String name) {
    final List<String> parts = name
        .trim()
        .split(' ')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'FX';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  Future<void> _toggleOnlineStatus(
    ProfileController profileController,
    OrderController orderController,
  ) async {
    final bool isOnline = profileController.profileModel?.active == 1;

    if (isOnline && (orderController.currentOrderList?.isNotEmpty ?? false)) {
      showCustomBottomSheet(
        child: const CustomConfirmationBottomSheet(
          title: 'Voc\u00ea n\u00e3o pode ficar offline agora',
          description:
              'Finalize a rota ativa para alterar sua disponibilidade.',
        ),
      );
      return;
    }

    if (isOnline) {
      showCustomBottomSheet(
        child: CustomConfirmationBottomSheet(
          title: 'Ficar offline?',
          description:
              'Tem certeza que deseja pausar o recebimento de pedidos?',
          image: Images.dmOfflineIcon,
          buttonWidget: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Row(
              children: [
                Expanded(
                  child: CustomButtonWidget(
                    onPressed: () => profileController.updateActiveStatus(),
                    buttonText: 'Sim, continuar',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CustomButtonWidget(
                    onPressed: () => Get.back(),
                    buttonText: 'Cancelar',
                    backgroundColor: Theme.of(
                      context,
                    ).disabledColor.withValues(alpha: 0.1),
                    fontColor: Theme.of(context).disabledColor,
                    isBorder: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        (!GetPlatform.isIOS && permission == LocationPermission.whileInUse)) {
      _checkLocationPermission(() => profileController.updateActiveStatus());
    } else {
      showCustomBottomSheet(
        child: CustomConfirmationBottomSheet(
          title: 'Ficar online?',
          description:
              'Voc\u00ea come\u00e7ar\u00e1 a receber solicita\u00e7\u00f5es de entrega agora.',
          buttonWidget: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Row(
              children: [
                Expanded(
                  child: CustomButtonWidget(
                    onPressed: () => profileController.updateActiveStatus(),
                    buttonText: 'Entrar online',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CustomButtonWidget(
                    onPressed: () => Get.back(),
                    buttonText: 'Cancelar',
                    backgroundColor: Theme.of(
                      context,
                    ).disabledColor.withValues(alpha: 0.1),
                    fontColor: Theme.of(context).disabledColor,
                    isBorder: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _checkLocationPermission(Function callback) async {
    LocationPermission permission = await Geolocator.requestPermission();
    permission = await Geolocator.checkPermission();

    while (Get.isDialogOpen == true) {
      Get.back();
    }

    final bool hasRequiredPermission =
        permission == LocationPermission.always ||
        (GetPlatform.isIOS && permission == LocationPermission.whileInUse);
    if (hasRequiredPermission) {
      callback();
      return;
    }

    if (permission == LocationPermission.denied) {
      Get.dialog(
        LocationAccessDialog(
          confirmText: 'Permitir localiza\u00e7\u00e3o',
          onConfirm: () async {
            Get.back();
            final LocationPermission updatedPermission =
                await Geolocator.requestPermission();
            final bool permissionReady =
                updatedPermission == LocationPermission.always ||
                (GetPlatform.isIOS &&
                    updatedPermission == LocationPermission.whileInUse);
            if (permissionReady) {
              callback();
              return;
            }
            await DeviceSettingsHelper.openLocationPermissionSettings();
            if (GetPlatform.isAndroid) {
              Future.delayed(
                const Duration(seconds: 3),
                () => _checkLocationPermission(callback),
              );
            }
          },
        ),
      );
    } else if (permission == LocationPermission.deniedForever ||
        (!GetPlatform.isIOS && permission == LocationPermission.whileInUse)) {
      Get.dialog(
        LocationAccessDialog(
          confirmText: 'Abrir configura\u00e7\u00f5es',
          onConfirm: () async {
            Get.back();
            await DeviceSettingsHelper.openLocationPermissionSettings();
            Future.delayed(const Duration(seconds: 3), () {
              if (GetPlatform.isAndroid) _checkLocationPermission(callback);
            });
          },
        ),
      );
    }
  }

  Widget _statusPillTop(
    String label,
    bool isOnline, {
    required bool hasActiveOrder,
    required VoidCallback onTap,
  }) {
    final Color color = isOnline
        ? const Color(0xFF1CAF68)
        : const Color(0xFF8A93A5);
    final String displayLabel = isOnline && !hasActiveOrder
        ? 'Dispon\u00edvel'
        : label;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            gradient: isOnline
                ? const LinearGradient(
                    colors: [Color(0xFF22BC71), Color(0xFF17A261)],
                  )
                : null,
            color: isOnline ? null : const Color(0xFFD6DCE6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isOnline
                  ? Colors.white.withValues(alpha: 0.16)
                  : const Color(0xFFCBD2DE),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.delivery_dining_rounded,
                color: Colors.white.withValues(alpha: 0.96),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: robotoBold.copyWith(
                  color: Colors.white,
                  fontSize: 16.5,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _earningTile(String title, String amount) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFBFD),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6EAF0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: robotoRegular.copyWith(
                color: const Color(0xFF6C7380),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              amount,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: robotoMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardContainer(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget permissionWarning({
    required String message,
    required Function() onTap,
    required Function() closeOnTap,
  }) {
    return GetPlatform.isAndroid
        ? Material(
            color: Theme.of(
              context,
            ).textTheme.bodyLarge!.color?.withValues(alpha: 0.7),
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(Dimensions.paddingSizeSmall),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Image.asset(
                        Images.allertIcon,
                        height: 20,
                        width: 20,
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              message,
                              maxLines: 2,
                              style: robotoRegular.copyWith(
                                fontSize: Dimensions.fontSizeSmall,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: Dimensions.paddingSizeSmall),
                          const Icon(
                            Icons.arrow_circle_right_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        : const SizedBox();
  }

  String _formatBrl(double? value) {
    return _brlFormatter.format(value ?? 0);
  }
}
