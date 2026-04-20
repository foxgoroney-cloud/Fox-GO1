import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart'
    hide NotificationVisibility;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fox_delivery_driver/features/auth/controllers/auth_controller.dart';
import 'package:fox_delivery_driver/features/chat/controllers/chat_controller.dart';
import 'package:fox_delivery_driver/features/dashboard/screens/dashboard_screen.dart';
import 'package:fox_delivery_driver/features/notification/controllers/notification_controller.dart';
import 'package:fox_delivery_driver/features/order/controllers/order_controller.dart';
import 'package:fox_delivery_driver/features/notification/domain/models/notification_body_model.dart';
import 'package:fox_delivery_driver/helper/custom_print_helper.dart';
import 'package:fox_delivery_driver/helper/route_helper.dart';
import 'package:fox_delivery_driver/util/app_constants.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

const String kIncomingOrderChannelId = 'fox_delivery_driver_incoming_orders';

class NormalizedPushPayload {
  final String type;
  final String? orderId;

  const NormalizedPushPayload({required this.type, required this.orderId});
}

class NotificationHelper {
  static NormalizedPushPayload normalizePayload(Map<String, dynamic> data) {
    final String type =
        (data['type'] ??
                data['body_loc_key'] ??
                data['notification_type'] ??
                '')
            .toString()
            .trim();
    final String rawOrderId =
        (data['order_id'] ??
                data['orderId'] ??
                data['id'] ??
                data['order'] ??
                '')
            .toString()
            .trim();

    return NormalizedPushPayload(
      type: type,
      orderId: rawOrderId.isEmpty ? null : rawOrderId,
    );
  }

  static String extractType(Map<String, dynamic> data) {
    return normalizePayload(data).type;
  }

  static int? extractOrderId(Map<String, dynamic> data) {
    return int.tryParse(normalizePayload(data).orderId ?? '');
  }

  static Future<void> initialize(
    FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
  ) async {
    var androidInitialize = const AndroidInitializationSettings(
      'notification_icon',
    );
    var iOSInitialize = const DarwinInitializationSettings();
    var initializationsSettings = InitializationSettings(
      android: androidInitialize,
      iOS: iOSInitialize,
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()!
        .requestNotificationsPermission();
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            kIncomingOrderChannelId,
            'Novas entregas',
            description: 'Alertas prioritarios para novas entregas',
            importance: Importance.max,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('notification'),
            enableVibration: true,
          ),
        );
    flutterLocalNotificationsPlugin.initialize(
      initializationsSettings,
      onDidReceiveNotificationResponse: (load) async {
        try {
          if (load.payload!.isNotEmpty) {
            NotificationBodyModel payload = NotificationBodyModel.fromJson(
              jsonDecode(load.payload!),
            );

            final Map<NotificationType, Function> notificationActions = {
              NotificationType.order: () => Get.toNamed(
                RouteHelper.getOrderDetailsRoute(
                  payload.orderId,
                  fromNotification: true,
                ),
              ),
              NotificationType.order_request: () async {
                await Get.find<OrderController>().handleIncomingOfferFromPush(
                  payload: {'order_id': payload.orderId?.toString() ?? ''},
                  shouldNavigateToHome: true,
                );
              },
              NotificationType.block: () =>
                  Get.offAllNamed(RouteHelper.getSignInRoute()),
              NotificationType.unblock: () =>
                  Get.offAllNamed(RouteHelper.getSignInRoute()),
              NotificationType.otp: () => null,
              NotificationType.unassign: () =>
                  Get.to(const DashboardScreen(pageIndex: 1)),
              NotificationType.message: () => Get.toNamed(
                RouteHelper.getChatRoute(
                  notificationBody: payload,
                  conversationId: payload.conversationId,
                  fromNotification: true,
                ),
              ),
              NotificationType.withdraw: () =>
                  Get.toNamed(RouteHelper.getMyAccountRoute()),
              NotificationType.general: () => Get.toNamed(
                RouteHelper.getNotificationRoute(fromNotification: true),
              ),
            };

            final action = notificationActions[payload.notificationType];
            if (action != null) {
              await action.call();
            }
          }
        } catch (_) {}
        return;
      },
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      customPrint('[PushFlow] onMessage (foreground) data=${message.data}');

      if (message.data['type'] == 'message' &&
          Get.currentRoute.startsWith(RouteHelper.chatScreen)) {
        if (Get.find<AuthController>().isLoggedIn()) {
          Get.find<ChatController>().getConversationList(1);
          if (Get.find<ChatController>().messageModel!.conversation!.id
                  .toString() ==
              message.data['conversation_id'].toString()) {
            Get.find<ChatController>().getMessages(
              1,
              NotificationBodyModel(
                notificationType: NotificationType.message,
                customerId: message.data['sender_type'] == AppConstants.user
                    ? 0
                    : null,
                vendorId: message.data['sender_type'] == AppConstants.vendor
                    ? 0
                    : null,
              ),
              null,
              int.parse(message.data['conversation_id'].toString()),
            );
          } else {
            NotificationHelper.showNotification(
              message,
              flutterLocalNotificationsPlugin,
            );
          }
        }
      } else if (message.data['type'] == 'message' &&
          Get.currentRoute.startsWith(RouteHelper.conversationListScreen)) {
        if (Get.find<AuthController>().isLoggedIn()) {
          Get.find<ChatController>().getConversationList(1);
        }
        NotificationHelper.showNotification(
          message,
          flutterLocalNotificationsPlugin,
        );
      } else if (message.data['type'] == 'otp') {
        NotificationHelper.showNotification(
          message,
          flutterLocalNotificationsPlugin,
        );
      } else if (message.data['type'] == 'deliveryman_referral') {
        NotificationHelper.showNotification(
          message,
          flutterLocalNotificationsPlugin,
        );
      } else {
        final String type = extractType(message.data);
        final int? orderId = extractOrderId(message.data);
        customPrint('[PushFlow] foreground type=$type orderId=$orderId');

        if (type == 'new_order' ||
            type == 'order_request' ||
            type == 'assign') {
          final OrderController orderController = Get.find<OrderController>();
          final bool isOnline = await orderController.canReceiveIncomingOffer();
          customPrint('[PushFlow] foreground onlineCheck=$isOnline');
          if (isOnline) {
            NotificationHelper.showMaxPriorityIncomingOrderAlert(
              message,
              flutterLocalNotificationsPlugin,
            );
            await orderController.handleIncomingOfferFromPush(
              payload: message.data,
              shouldNavigateToHome: true,
            );
          } else {
            customPrint(
              '[PushFlow] Ignorando nova entrega porque entregador estÃ¡ offline.',
            );
          }
          orderController.getRunningOrders(1, status: 'all');
          orderController.getOrderCount(orderController.orderType);
        }

        if (type != 'assign' &&
            type != 'new_order' &&
            type != 'order_request') {
          NotificationHelper.showNotification(
            message,
            flutterLocalNotificationsPlugin,
          );
          Get.find<OrderController>().getRunningOrders(1, status: 'all');
          Get.find<OrderController>().getOrderCount(
            Get.find<OrderController>().orderType,
          );
          Get.find<OrderController>().getLatestOrders();
          Get.find<NotificationController>().getNotificationList();
        }
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      customPrint('[PushFlow] onMessageOpenedApp data=${message.data}');
      try {
        if (message.data.isNotEmpty) {
          customPrint(
            '[PushFlow] opened-app type=${extractType(message.data)} orderId=${extractOrderId(message.data)}',
          );
          NotificationBodyModel notificationBody = convertNotification(
            message.data,
          )!;

          final Map<NotificationType, Function> notificationActions = {
            NotificationType.order: () => Get.toNamed(
              RouteHelper.getOrderDetailsRoute(
                int.parse(message.data['order_id']),
                fromNotification: true,
              ),
            ),
            NotificationType.order_request: () async {
              await Get.find<OrderController>().handleIncomingOfferFromPush(
                payload: message.data,
                shouldNavigateToHome: true,
              );
            },
            NotificationType.block: () =>
                Get.offAllNamed(RouteHelper.getSignInRoute()),
            NotificationType.unblock: () =>
                Get.offAllNamed(RouteHelper.getSignInRoute()),
            NotificationType.otp: () => null,
            NotificationType.unassign: () =>
                Get.to(const DashboardScreen(pageIndex: 1)),
            NotificationType.message: () => Get.toNamed(
              RouteHelper.getChatRoute(
                notificationBody: notificationBody,
                conversationId: notificationBody.conversationId,
                fromNotification: true,
              ),
            ),
            NotificationType.withdraw: () =>
                Get.toNamed(RouteHelper.getMyAccountRoute()),
            NotificationType.general: () => Get.toNamed(
              RouteHelper.getNotificationRoute(fromNotification: true),
            ),
          };

          final action = notificationActions[notificationBody.notificationType];
          if (action != null) {
            await action.call();
          }
        }
      } catch (_) {}
    });
  }

  static Future<void> showNotification(
    RemoteMessage message,
    FlutterLocalNotificationsPlugin fln,
  ) async {
    if (!GetPlatform.isIOS) {
      String? title;
      String? body;
      String? image;
      NotificationBodyModel? notificationBody = convertNotification(
        message.data,
      );

      title = message.data['title'];
      body = message.data['body'];
      image =
          (message.data['image'] != null && message.data['image'].isNotEmpty)
          ? message.data['image'].startsWith('http')
                ? message.data['image']
                : '${AppConstants.baseUrl}/storage/app/public/notification/${message.data['image']}'
          : null;

      if (image != null && image.isNotEmpty) {
        try {
          await showBigPictureNotificationHiddenLargeIcon(
            title,
            body,
            notificationBody,
            image,
            fln,
          );
        } catch (e) {
          await showBigTextNotification(title, body!, notificationBody, fln);
        }
      } else {
        await showBigTextNotification(title, body!, notificationBody, fln);
      }
    }
  }

  static Future<void> showTextNotification(
    String title,
    String body,
    NotificationBodyModel notificationBody,
    FlutterLocalNotificationsPlugin fln,
  ) async {
    final bool isIncomingOrder =
        notificationBody.notificationType == NotificationType.order_request;
    final AndroidNotificationDetails resolvedAndroidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          isIncomingOrder
              ? kIncomingOrderChannelId
              : AppConstants.notificationChannelId,
          isIncomingOrder ? 'Novas entregas' : AppConstants.appName,
          playSound: true,
          importance: Importance.max,
          priority: Priority.max,
          sound: const RawResourceAndroidNotificationSound('notification'),
          category: isIncomingOrder
              ? AndroidNotificationCategory.call
              : AndroidNotificationCategory.message,
          fullScreenIntent: isIncomingOrder,
          visibility: isIncomingOrder ? NotificationVisibility.public : null,
          timeoutAfter: isIncomingOrder ? 30000 : null,
        );
    await fln.show(
      0,
      title,
      body,
      NotificationDetails(android: resolvedAndroidPlatformChannelSpecifics),
      payload: jsonEncode(notificationBody.toJson()),
    );
  }

  static Future<void> showMaxPriorityIncomingOrderAlert(
    RemoteMessage message,
    FlutterLocalNotificationsPlugin fln,
  ) async {
    if (GetPlatform.isIOS) {
      return;
    }

    final NotificationBodyModel? notificationBody = convertNotification(
      message.data,
    );
    final String title = (message.data['title']?.toString().isNotEmpty ?? false)
        ? message.data['title'].toString()
        : 'Nova entrega disponÃ­vel';
    final String body = (message.data['body']?.toString().isNotEmpty ?? false)
        ? message.data['body'].toString()
        : 'Abra para aceitar ou recusar a corrida.';

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          kIncomingOrderChannelId,
          'Novas entregas',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('notification'),
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          visibility: NotificationVisibility.public,
          autoCancel: true,
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );
    await fln.show(
      999001,
      title,
      body,
      details,
      payload: notificationBody != null
          ? jsonEncode(notificationBody.toJson())
          : null,
    );
  }

  static Future<void> showBigTextNotification(
    String? title,
    String body,
    NotificationBodyModel? notificationBody,
    FlutterLocalNotificationsPlugin fln,
  ) async {
    BigTextStyleInformation bigTextStyleInformation = BigTextStyleInformation(
      body,
      htmlFormatBigText: true,
      contentTitle: title,
      htmlFormatContentTitle: true,
    );
    final bool isIncomingOrder =
        notificationBody?.notificationType == NotificationType.order_request;
    AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          isIncomingOrder
              ? kIncomingOrderChannelId
              : AppConstants.notificationChannelId,
          isIncomingOrder ? 'Novas entregas' : AppConstants.appName,
          importance: Importance.max,
          styleInformation: bigTextStyleInformation,
          priority: Priority.max,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('notification'),
          category: isIncomingOrder
              ? AndroidNotificationCategory.call
              : AndroidNotificationCategory.message,
          fullScreenIntent: isIncomingOrder,
          visibility: isIncomingOrder ? NotificationVisibility.public : null,
          timeoutAfter: isIncomingOrder ? 30000 : null,
        );
    NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    await fln.show(
      0,
      title,
      body,
      platformChannelSpecifics,
      payload: notificationBody != null
          ? jsonEncode(notificationBody.toJson())
          : null,
    );
  }

  static Future<void> showBigPictureNotificationHiddenLargeIcon(
    String? title,
    String? body,
    NotificationBodyModel? notificationBody,
    String image,
    FlutterLocalNotificationsPlugin fln,
  ) async {
    final String largeIconPath = await _downloadAndSaveFile(image, 'largeIcon');
    final String bigPicturePath = await _downloadAndSaveFile(
      image,
      'bigPicture',
    );
    final BigPictureStyleInformation bigPictureStyleInformation =
        BigPictureStyleInformation(
          FilePathAndroidBitmap(bigPicturePath),
          hideExpandedLargeIcon: true,
          contentTitle: title,
          htmlFormatContentTitle: true,
          summaryText: body,
          htmlFormatSummaryText: true,
        );
    final bool isIncomingOrder =
        notificationBody?.notificationType == NotificationType.order_request;
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          isIncomingOrder
              ? kIncomingOrderChannelId
              : AppConstants.notificationChannelId,
          isIncomingOrder ? 'Novas entregas' : AppConstants.appName,
          largeIcon: FilePathAndroidBitmap(largeIconPath),
          priority: Priority.max,
          playSound: true,
          styleInformation: bigPictureStyleInformation,
          importance: Importance.max,
          sound: const RawResourceAndroidNotificationSound('notification'),
          category: isIncomingOrder
              ? AndroidNotificationCategory.call
              : AndroidNotificationCategory.message,
          fullScreenIntent: isIncomingOrder,
          visibility: isIncomingOrder ? NotificationVisibility.public : null,
          timeoutAfter: isIncomingOrder ? 30000 : null,
        );
    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    await fln.show(
      0,
      title,
      body,
      platformChannelSpecifics,
      payload: notificationBody != null
          ? jsonEncode(notificationBody.toJson())
          : null,
    );
  }

  static Future<String> _downloadAndSaveFile(
    String url,
    String fileName,
  ) async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final String filePath = '${directory.path}/$fileName';
    final http.Response response = await http.get(Uri.parse(url));
    final File file = File(filePath);
    await file.writeAsBytes(response.bodyBytes);
    return filePath;
  }

  static NotificationBodyModel? convertNotification(Map<String, dynamic> data) {
    final NormalizedPushPayload normalizedPayload = normalizePayload(data);
    final String type = normalizedPayload.type;
    final int? orderId = int.tryParse(normalizedPayload.orderId ?? '');

    switch (type) {
      case 'cash_collect':
        return NotificationBodyModel(
          notificationType: NotificationType.general,
        );
      case 'unassign':
        return NotificationBodyModel(
          notificationType: NotificationType.unassign,
        );
      case 'order_status':
        return orderId == null
            ? NotificationBodyModel(notificationType: NotificationType.general)
            : NotificationBodyModel(
                orderId: orderId,
                notificationType: NotificationType.order,
              );
      case 'order_request':
      case 'new_order':
      case 'assign':
        return NotificationBodyModel(
          orderId: orderId,
          notificationType: NotificationType.order_request,
        );
      case 'block':
        return NotificationBodyModel(notificationType: NotificationType.block);
      case 'unblock':
        return NotificationBodyModel(
          notificationType: NotificationType.unblock,
        );
      case 'otp':
        return NotificationBodyModel(notificationType: NotificationType.otp);
      case 'message':
        return _handleMessageNotification(data);
      case 'withdraw':
        return NotificationBodyModel(
          notificationType: NotificationType.withdraw,
        );
      case 'deliveryman_referral':
        return NotificationBodyModel(
          notificationType: NotificationType.general,
        );
      default:
        return NotificationBodyModel(
          notificationType: NotificationType.general,
        );
    }
  }

  static NotificationBodyModel _handleMessageNotification(
    Map<String, dynamic> data,
  ) {
    final conversationId = data['conversation_id'];
    final senderType = data['sender_type'];

    return NotificationBodyModel(
      conversationId: (conversationId != null && conversationId.isNotEmpty)
          ? int.parse(conversationId)
          : null,
      notificationType: NotificationType.message,
      type: senderType == AppConstants.user
          ? AppConstants.user
          : AppConstants.vendor,
    );
  }
}

final AudioPlayer _audioPlayer = AudioPlayer();

/// Background FCM message handler
@pragma('vm:entry-point')
Future<void> myBackgroundMessageHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  customPrint("[PushFlow] onBackground data=${message.data}");
  customPrint(
    "[PushFlow] onBackground type=${NotificationHelper.extractType(message.data)} orderId=${NotificationHelper.extractOrderId(message.data)}",
  );

  final notificationBody = NotificationHelper.convertNotification(message.data);

  if (notificationBody != null &&
      (notificationBody.notificationType == NotificationType.order ||
          notificationBody.notificationType ==
              NotificationType.order_request)) {
    FlutterForegroundTask.initCommunicationPort();
    await _initService();
    await _startService(
      notificationBody.orderId?.toString(),
      notificationBody.notificationType!,
    );
  }
}

/// Initialize Foreground Service
@pragma('vm:entry-point')
Future<void> _initService() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: AppConstants.notificationChannelId,
      channelName: 'Fox Delivery',
      channelDescription: 'Fox Delivery foreground service.',
      onlyAlertOnce: false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

/// Start Foreground Service
@pragma('vm:entry-point')
Future<ServiceRequestResult> _startService(
  String? orderId,
  NotificationType notificationType,
) async {
  if (await FlutterForegroundTask.isRunningService) {
    return FlutterForegroundTask.restartService();
  } else {
    return FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: notificationType == NotificationType.order_request
          ? 'Fox Delivery'
          : 'Fox Delivery: novo pedido ($orderId)',
      notificationText: notificationType == NotificationType.order_request
          ? 'Novo pedido disponivel para avaliacao.'
          : 'Abra o app para ver os detalhes do pedido.',
      callback: startCallback,
    );
  }
}

/// Stop Foreground Service
@pragma('vm:entry-point')
Future<ServiceRequestResult> stopService() async {
  try {
    await _audioPlayer.stop();
    await _audioPlayer.dispose();
  } catch (e) {
    customPrint('Audio dispose error: $e');
  }
  return FlutterForegroundTask.stopService();
}

/// Foreground Service entry point
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

/// Foreground Service Task Handler
class MyTaskHandler extends TaskHandler {
  AudioPlayer? _localPlayer;

  void _playAudio() {
    _localPlayer?.play(AssetSource('notification.mp3'));
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _localPlayer = AudioPlayer();
    _playAudio();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _playAudio();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _localPlayer?.dispose();
    await stopService();
  }

  @override
  void onReceiveData(Object data) {
    _playAudio();
  }

  @override
  void onNotificationButtonPressed(String id) {
    customPrint('onNotificationButtonPressed: $id');
    if (id == '1') {
      FlutterForegroundTask.launchApp('/');
    }
    stopService();
  }

  @override
  void onNotificationPressed() {
    customPrint('onNotificationPressed');
    FlutterForegroundTask.launchApp('/');
    stopService();
  }

  @override
  void onNotificationDismissed() {
    FlutterForegroundTask.updateService(
      notificationTitle: 'Fox Delivery',
      notificationText: 'Abra o app para ver os detalhes do pedido.',
    );
  }
}
