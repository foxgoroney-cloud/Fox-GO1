import 'package:flutter/cupertino.dart';
import 'package:fox_delivery_driver/util/dimensions.dart';
import 'package:fox_delivery_driver/util/styles.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProfileButtonWidget extends StatelessWidget {
  final IconData? icon;
  final String? iconImage;
  final String title;
  final bool? isButtonActive;
  final Function onTap;
  const ProfileButtonWidget({
    super.key, this.icon, required this.title, required this.onTap,
    this.isButtonActive, this.iconImage,
  }) : assert (icon != null || iconImage != null, 'Either icon or iconImage must be provided');

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap as void Function()?,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: Dimensions.paddingSizeDefault,
          vertical: isButtonActive != null ? Dimensions.paddingSizeSmall : Dimensions.paddingSizeDefault,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).disabledColor.withValues(alpha: 0.12)),
          boxShadow: [BoxShadow(color: Colors.grey[Get.isDarkMode ? 900 : 100]!, spreadRadius: 0, blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(children: [

          iconImage != null ? Image.asset(
            iconImage!,
            height: 25, width: 25,
            color: Theme.of(context).disabledColor,
          ) : Icon(icon, size: 25, color: Theme.of(context).disabledColor),

          const SizedBox(width: Dimensions.paddingSizeDefault),

          Expanded(child: Text(title, style: robotoMedium.copyWith(fontSize: Dimensions.fontSizeDefault))),

          isButtonActive != null ? Transform.scale(
            scale: 0.7,
            child: CupertinoSwitch(
              value: isButtonActive!,
              onChanged: (bool? value) => onTap(),
              activeTrackColor: Theme.of(context).primaryColor,
              inactiveTrackColor: Theme.of(context).primaryColor.withValues(alpha: 0.5),
            ),
          ) : const SizedBox(),

        ]),
      ),
    );
  }
}
