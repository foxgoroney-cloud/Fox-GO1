import 'dart:async';
import 'dart:io';
import 'package:fox_delivery_driver/features/auth/controllers/auth_controller.dart';
import 'package:fox_delivery_driver/features/order/controllers/order_controller.dart';
import 'package:fox_delivery_driver/features/disbursement/helper/disbursement_helper.dart';
import 'package:fox_delivery_driver/features/profile/controllers/profile_controller.dart';
import 'package:fox_delivery_driver/helper/notification_helper.dart';
import 'package:fox_delivery_driver/helper/route_helper.dart';
import 'package:fox_delivery_driver/main.dart';
import 'package:fox_delivery_driver/util/dimensions.dart';
import 'package:fox_delivery_driver/common/widgets/custom_alert_dialog_widget.dart';
import 'package:fox_delivery_driver/features/dashboard/widgets/bottom_nav_item_widget.dart';
import 'package:fox_delivery_driver/features/dashboard/widgets/new_order_offer_sheet_widget.dart';
import 'package:fox_delivery_driver/features/home/screens/home_screen.dart';
import 'package:fox_delivery_driver/features/profile/screens/profile_screen.dart';
import 'package:fox_delivery_driver/features/order/screens/order_request_screen.dart';
import 'package:fox_delivery_driver/features/order/screens/order_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class DashboardScreen extends StatefulWidget {
  final int pageIndex;
  final bool fromOrderDetails;
  final int? initialIncomingOrderId;

  const DashboardScreen({
    super.key,
    required this.pageIndex,
    this.fromOrderDetails = false,
    this.initialIncomingOrderId,
  });

  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  PageController? _pageController;
  int _pageIndex = 0;
  late List<Widget> _screens;
  final _channel = const MethodChannel('fox.delivery/app_retain');
  late StreamSubscription _stream;
  Timer? _foregroundSyncTimer;
  DisbursementHelper disbursementHelper = DisbursementHelper();
  bool _canExit = false;
  int? _lastPresentedOfferId;

  @override
  void initState() {
    super.initState();

    _pageIndex = widget.pageIndex;
    _pageController = PageController(initialPage: widget.pageIndex);

    _screens = [
      HomeScreen(onNavigateToOrders: () => _setPage(1)),
      OrderRequestScreen(onTap: () => _setPage(0)),
      const OrderScreen(),
      const ProfileScreen(),
    ];

    showDisbursementWarningMessage();
    Get.find<OrderController>().getLatestOrders();
    Get.find<OrderController>().restorePendingIncomingOffer();
    _startForegroundRealtimeSync();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleInitialIncomingOrderFromRoute();
    });

    _stream = FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final String type = NotificationHelper.extractType(message.data);
      if (type != 'assign' &&
          type != 'new_order' &&
          type != 'message' &&
          type != 'order_request' &&
          type != 'order_status') {
        NotificationHelper.showNotification(
          message,
          flutterLocalNotificationsPlugin,
        );
      }
      if (type == 'new_order' || type == 'order_request' || type == 'assign') {
        await Get.find<OrderController>().handleIncomingOfferFromPush(
          payload: message.data,
        );
        await Get.find<OrderController>().getRunningOrders(
          Get.find<OrderController>().offset,
          status: 'all',
        );
        await Get.find<OrderController>().getOrderCount(
          Get.find<OrderController>().orderType,
        );
        if (mounted) {
          _setPage(0);
          await _presentIncomingOfferSheetIfAvailable();
        }
      } else if (type == 'block') {
        Get.find<AuthController>().clearSharedData();
        Get.find<ProfileController>().stopLocationRecord();
        Get.offAllNamed(RouteHelper.getSignInRoute());
      }
    });
  }

  Future<void> showDisbursementWarningMessage() async {
    if (!widget.fromOrderDetails) {
      disbursementHelper.enableDisbursementWarningMessage(true);
    }
  }

  void _navigateRequestPage() {
    if (Get.find<ProfileController>().profileModel != null &&
        Get.find<ProfileController>().profileModel!.active == 1 &&
        Get.find<OrderController>().currentOrderList != null &&
        Get.find<OrderController>().currentOrderList!.isEmpty) {
      _setPage(1);
    } else {
      if (Get.find<ProfileController>().profileModel == null ||
          Get.find<ProfileController>().profileModel!.active == 0) {
        Get.dialog(
          CustomAlertDialogWidget(
            description: 'you_are_offline_now'.tr,
            onOkPressed: () => Get.back(),
          ),
        );
      } else {
        _setPage(1);
      }
    }
  }

  @override
  void dispose() {
    _foregroundSyncTimer?.cancel();
    _stream.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (_pageIndex != 0) {
          _setPage(0);
        } else {
          if (_canExit) {
            if (GetPlatform.isAndroid) {
              if (Get.find<ProfileController>().profileModel!.active == 1) {
                _channel.invokeMethod('sendToBackground');
              }
              SystemNavigator.pop();
            } else if (GetPlatform.isIOS) {
              exit(0);
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'back_press_again_to_exit'.tr,
                style: const TextStyle(color: Colors.white),
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
              margin: const EdgeInsets.all(Dimensions.paddingSizeSmall),
            ),
          );
          _canExit = true;

          Timer(const Duration(seconds: 2), () {
            _canExit = false;
          });
        }
      },
      child: Scaffold(
        extendBody: true,
        backgroundColor: const Color(0xFFF7F8FB),
        bottomNavigationBar: GetPlatform.isDesktop
            ? const SizedBox()
            : SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withValues(alpha: 0.97),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).disabledColor.withValues(alpha: 0.14),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 26,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    height: 78,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                      child: Row(
                        children: [
                          BottomNavItemWidget(
                            icon: Icons.home_outlined,
                            selectedIcon: Icons.home_rounded,
                            label: 'In\u00edcio',
                            isSelected: _pageIndex == 0,
                            onTap: () => _setPage(0),
                          ),
                          BottomNavItemWidget(
                            icon: Icons.account_balance_wallet_outlined,
                            selectedIcon: Icons.account_balance_wallet_rounded,
                            label: 'Financeiro',
                            onTap: () =>
                                Get.toNamed(RouteHelper.getMyAccountRoute()),
                          ),
                          BottomNavItemWidget(
                            icon: Icons.headset_mic_outlined,
                            selectedIcon: Icons.headset_mic_rounded,
                            label: 'Ajuda',
                            onTap: () => Get.toNamed(
                              RouteHelper.getConversationListRoute(),
                            ),
                          ),
                          BottomNavItemWidget(
                            icon: Icons.grid_view_rounded,
                            selectedIcon: Icons.grid_view_rounded,
                            label: 'Mais',
                            isSelected: _pageIndex == 3,
                            onTap: () => _setPage(3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        body: PageView.builder(
          controller: _pageController,
          itemCount: _screens.length,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, index) {
            return _screens[index];
          },
        ),
      ),
    );
  }

  void _setPage(int pageIndex) {
    setState(() {
      _pageController!.jumpToPage(pageIndex);
      _pageIndex = pageIndex;
    });
  }

  Future<void> _handleInitialIncomingOrderFromRoute() async {
    final int? initialOrderId = widget.initialIncomingOrderId;
    if (initialOrderId == null || !mounted) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) {
      return;
    }

    final OrderController orderController = Get.find<OrderController>();
    await orderController.handleIncomingOfferFromPush(
      payload: <String, dynamic>{
        'type': 'new_order',
        'order_id': initialOrderId.toString(),
      },
    );
    await orderController.getRunningOrders(
      orderController.offset,
      status: 'all',
    );
    await orderController.getOrderCount(orderController.orderType);

    if (!mounted) {
      return;
    }

    _setPage(0);
    await _presentIncomingOfferSheetIfAvailable();
  }

  Future<void> _presentIncomingOfferSheetIfAvailable() async {
    if (!mounted || Get.isDialogOpen == true) {
      return;
    }

    final OrderController orderController = Get.find<OrderController>();
    final offerOrder = orderController.incomingOfferOrder;
    if (offerOrder?.id == null) {
      return;
    }

    if (_lastPresentedOfferId == offerOrder!.id) {
      return;
    }
    _lastPresentedOfferId = offerOrder.id;

    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || Get.isDialogOpen == true) {
      return;
    }

    await showGeneralDialog(
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

  void _startForegroundRealtimeSync() {
    _foregroundSyncTimer?.cancel();
    _foregroundSyncTimer = Timer.periodic(const Duration(seconds: 8), (
      _,
    ) async {
      if (!mounted) {
        return;
      }
      final ProfileController profileController = Get.find<ProfileController>();
      final bool isOnline = profileController.profileModel?.active == 1;
      if (!isOnline) {
        return;
      }

      final OrderController orderController = Get.find<OrderController>();
      await orderController.getLatestOrders();
      await orderController.getRunningOrders(
        1,
        status: 'all',
        willUpdate: false,
      );
      await orderController.getOrderCount(orderController.orderType);
    });
  }
}
