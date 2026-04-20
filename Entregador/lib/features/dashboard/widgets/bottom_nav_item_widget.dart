import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fox_delivery_driver/common/widgets/custom_ink_well_widget.dart';
import 'package:fox_delivery_driver/features/order/controllers/order_controller.dart';
import 'package:fox_delivery_driver/util/dimensions.dart';
import 'package:fox_delivery_driver/util/styles.dart';

class BottomNavItemWidget extends StatelessWidget {
  final String? iconData;
  final IconData? icon;
  final IconData? selectedIcon;
  final Function() onTap;
  final bool isSelected;
  final int? pageIndex;
  final String label;

  const BottomNavItemWidget({
    super.key,
    this.iconData,
    this.icon,
    this.selectedIcon,
    required this.onTap,
    this.isSelected = false,
    this.pageIndex,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final Color itemColor = isSelected ? Theme.of(context).primaryColor : const Color(0xFF7A8394);
    return Expanded(
      child: CustomInkWellWidget(
        onTap: onTap,
        radius: 18,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  icon != null
                      ? Icon(isSelected ? (selectedIcon ?? icon) : icon, color: itemColor, size: 21)
                      : Image.asset(iconData!, color: itemColor, height: 20),
                  if (pageIndex == 1)
                    Positioned(
                      top: -5,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
                        ),
                        child: GetBuilder<OrderController>(builder: (orderController) {
                          return Text(
                            orderController.latestOrderList?.length.toString() ?? '0',
                            style: robotoRegular.copyWith(fontSize: Dimensions.fontSizeExtraSmall, color: Colors.white),
                          );
                        }),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: robotoMedium.copyWith(
                fontSize: 11.5,
                color: itemColor,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
