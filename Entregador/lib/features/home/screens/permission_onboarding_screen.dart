import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fox_delivery_driver/common/widgets/custom_button_widget.dart';
import 'package:fox_delivery_driver/helper/device_settings_helper.dart';
import 'package:fox_delivery_driver/helper/route_helper.dart';
import 'package:fox_delivery_driver/util/app_constants.dart';
import 'package:fox_delivery_driver/util/dimensions.dart';
import 'package:fox_delivery_driver/util/styles.dart';

class PermissionOnboardingScreen extends StatefulWidget {
  const PermissionOnboardingScreen({super.key});

  static Future<bool> shouldShow() async {
    final SharedPreferences prefs = Get.find<SharedPreferences>();
    final bool alreadyShown =
        prefs.getBool(AppConstants.permissionOnboardingShown) ?? false;

    if (!alreadyShown) {
      return true;
    }

    return await _hasMissingEssentialPermission();
  }

  static Future<bool> _hasMissingEssentialPermission() async {
    final LocationPermission locationPermission =
        await Geolocator.checkPermission();
    final bool locationMissing =
        locationPermission == LocationPermission.denied ||
        locationPermission == LocationPermission.deniedForever ||
        (!GetPlatform.isIOS &&
            locationPermission == LocationPermission.whileInUse);

    final PermissionStatus notificationStatus =
        await Permission.notification.status;
    final bool notificationMissing =
        notificationStatus.isDenied || notificationStatus.isPermanentlyDenied;

    final bool overlayMissing =
        GetPlatform.isAndroid &&
        !(await Permission.systemAlertWindow.status.isGranted);

    return locationMissing || notificationMissing || overlayMissing;
  }

  @override
  State<PermissionOnboardingScreen> createState() =>
      _PermissionOnboardingScreenState();
}

class _PermissionOnboardingScreenState
    extends State<PermissionOnboardingScreen> {
  int _stepIndex = 0;
  final List<_PermissionStepType> _steps = const [
    _PermissionStepType.location,
    _PermissionStepType.notification,
    _PermissionStepType.overlay,
    _PermissionStepType.background,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapFlow());
  }

  Future<void> _bootstrapFlow() async {
    final SharedPreferences prefs = Get.find<SharedPreferences>();
    final bool alreadyShown =
        prefs.getBool(AppConstants.permissionOnboardingShown) ?? false;

    if (alreadyShown &&
        !(await PermissionOnboardingScreen._hasMissingEssentialPermission())) {
      _goToHome();
      return;
    }

    await _skipGrantedSteps();
  }

  Future<void> _skipGrantedSteps() async {
    int nextIndex = _stepIndex;
    while (nextIndex < _steps.length) {
      if (await _isStepGranted(_steps[nextIndex])) {
        nextIndex++;
      } else {
        break;
      }
    }

    if (nextIndex >= _steps.length) {
      await _finishFlow();
      return;
    }

    if (mounted) {
      setState(() => _stepIndex = nextIndex);
    }
  }

  Future<bool> _isStepGranted(_PermissionStepType step) async {
    switch (step) {
      case _PermissionStepType.location:
        final permission = await Geolocator.checkPermission();
        return permission == LocationPermission.always ||
            (GetPlatform.isIOS && permission == LocationPermission.whileInUse);
      case _PermissionStepType.notification:
        return await Permission.notification.status.isGranted;
      case _PermissionStepType.overlay:
        if (!GetPlatform.isAndroid) {
          return true;
        }
        return await Permission.systemAlertWindow.status.isGranted;
      case _PermissionStepType.background:
        if (!GetPlatform.isAndroid) {
          return true;
        }
        return await Permission.ignoreBatteryOptimizations.status.isGranted;
    }
  }

  Future<void> _requestCurrentStep() async {
    final currentStep = _steps[_stepIndex];

    switch (currentStep) {
      case _PermissionStepType.location:
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        final bool hasRequiredPermission =
            permission == LocationPermission.always ||
            (GetPlatform.isIOS && permission == LocationPermission.whileInUse);
        if (!hasRequiredPermission) {
          await DeviceSettingsHelper.openLocationPermissionSettings();
        }
        break;
      case _PermissionStepType.notification:
        final status = await Permission.notification.request();
        if (!status.isGranted) {
          await DeviceSettingsHelper.openNotificationSettings();
        }
        break;
      case _PermissionStepType.overlay:
        if (!GetPlatform.isAndroid) {
          await _nextStep();
          return;
        }
        final PermissionStatus status = await Permission.systemAlertWindow
            .request();
        if (!status.isGranted) {
          await openAppSettings();
        }
        break;
      case _PermissionStepType.background:
        if (!GetPlatform.isAndroid) {
          await _nextStep();
          return;
        }
        await DeviceSettingsHelper.openBatteryOptimizationSettings();
        break;
    }

    await _nextStep();
  }

  Future<void> _nextStep() async {
    if (_stepIndex >= _steps.length - 1) {
      await _finishFlow();
      return;
    }

    if (mounted) {
      setState(() => _stepIndex++);
    }
    await _skipGrantedSteps();
  }

  Future<void> _finishFlow() async {
    final SharedPreferences prefs = Get.find<SharedPreferences>();
    await prefs.setBool(AppConstants.permissionOnboardingShown, true);
    _goToHome();
  }

  void _goToHome() {
    Get.offAllNamed(RouteHelper.getInitialRoute());
  }

  Widget _buildReasonRow(String reason) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFF1CAF68),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Expanded(child: Text(reason, style: robotoRegular)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final _PermissionStepData step = _stepData(_steps[_stepIndex]);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: 620,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configura\u00e7\u00e3o inicial de permiss\u00f5es',
                    style: robotoBold.copyWith(
                      fontSize: Dimensions.fontSizeExtraLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Etapa ${_stepIndex + 1} de ${_steps.length}',
                    style: robotoRegular.copyWith(
                      color: Theme.of(context).disabledColor,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    step.title,
                    style: robotoBold.copyWith(
                      fontSize: Dimensions.fontSizeLarge,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    step.description,
                    style: robotoRegular.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  ...step.reasons.map(_buildReasonRow),
                  if (step.note != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      step.note!,
                      style: robotoRegular.copyWith(
                        color: Theme.of(context).disabledColor,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: CustomButtonWidget(
                          buttonText: 'Agora n\u00e3o',
                          onPressed: _nextStep,
                          backgroundColor: Theme.of(
                            context,
                          ).disabledColor.withValues(alpha: 0.15),
                          fontColor: Theme.of(context).disabledColor,
                          isBorder: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CustomButtonWidget(
                          buttonText: step.confirmButton,
                          onPressed: _requestCurrentStep,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  _PermissionStepData _stepData(_PermissionStepType step) {
    switch (step) {
      case _PermissionStepType.location:
        return const _PermissionStepData(
          title: 'Permitir acesso \u00e0 localiza\u00e7\u00e3o',
          description:
              'A Fox Delivery precisa da sua localiza\u00e7\u00e3o para mostrar sua posi\u00e7\u00e3o no mapa, calcular rotas e ajudar voc\u00ea a receber pedidos pr\u00f3ximos.',
          reasons: [
            'Mostrar sua localiza\u00e7\u00e3o em tempo real no mapa',
            'Melhorar a precis\u00e3o das rotas e do tempo estimado',
            'Ajudar no acompanhamento das entregas, inclusive em segundo plano',
          ],
          note:
              'Sua localiza\u00e7\u00e3o \u00e9 usada apenas para a opera\u00e7\u00e3o das entregas.',
          confirmButton: 'Continuar',
        );
      case _PermissionStepType.notification:
        return const _PermissionStepData(
          title: 'Permitir notifica\u00e7\u00f5es',
          description:
              'A Fox Delivery envia notifica\u00e7\u00f5es para avisar sobre novos pedidos e atualiza\u00e7\u00f5es importantes da sua rota.',
          reasons: [
            'Receber alertas de novos pedidos imediatamente',
            'Acompanhar mudan\u00e7as no status da entrega',
            'Evitar perda de oportunidades por falta de aviso',
          ],
          confirmButton: 'Continuar',
        );
      case _PermissionStepType.overlay:
        return const _PermissionStepData(
          title: 'Permitir sobreposi\u00e7\u00e3o na tela',
          description:
              'A Fox Delivery precisa dessa permiss\u00e3o para abrir o card de nova entrega por cima do app e da tela bloqueada.',
          reasons: [
            'Mostrar o card da nova entrega imediatamente',
            'Destacar pedidos priorit\u00e1rios sem depender da notifica\u00e7\u00e3o comum',
            'Permitir aceitar ou recusar a corrida mais r\u00e1pido',
          ],
          note:
              'No Android essa permiss\u00e3o costuma aparecer como "Exibir sobre outros apps".',
          confirmButton: 'Liberar card',
        );
      case _PermissionStepType.background:
        return const _PermissionStepData(
          title: 'Permitir atividade em segundo plano',
          description:
              'A Fox Delivery precisa enviar alertas de novos pedidos mesmo quando o app n\u00e3o estiver aberto na tela.',
          reasons: [
            'Continuar recebendo pedidos fora da tela principal',
            'Reduzir atrasos no recebimento de alertas',
            'Manter seu app pronto para novas corridas durante o dia',
          ],
          note:
              'Voc\u00ea pode ajustar isso nas configura\u00e7\u00f5es de bateria do aparelho, deixando a Fox Delivery sem restri\u00e7\u00f5es.',
          confirmButton: 'Abrir configura\u00e7\u00f5es',
        );
    }
  }
}

enum _PermissionStepType { location, notification, overlay, background }

class _PermissionStepData {
  final String title;
  final String description;
  final List<String> reasons;
  final String? note;
  final String confirmButton;

  const _PermissionStepData({
    required this.title,
    required this.description,
    required this.reasons,
    this.note,
    required this.confirmButton,
  });
}
