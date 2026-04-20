import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fox_delivery_driver/common/widgets/custom_asset_image_widget.dart';
import 'package:fox_delivery_driver/features/disbursement/controllers/disbursement_controller.dart';
import 'package:fox_delivery_driver/util/dimensions.dart';
import 'package:fox_delivery_driver/util/images.dart';
import 'package:fox_delivery_driver/util/styles.dart';
import 'package:fox_delivery_driver/common/widgets/custom_button_widget.dart';

class ConfirmDialogWidget extends StatelessWidget {
  final int id;
  const ConfirmDialogWidget({super.key, required this.id, });

  @override
  Widget build(BuildContext context) {
    return GetBuilder<DisbursementController>(builder: (disbursementController) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Dimensions.radiusDefault)),
        insetPadding: const EdgeInsets.all(30),
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              Align(
                alignment: Alignment.topRight,
                child: InkWell(
                  onTap: () => Get.back(),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Icon(Icons.close, size: 20, color: Theme.of(context).disabledColor),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(left: Dimensions.paddingSizeLarge, right: Dimensions.paddingSizeLarge, bottom: Dimensions.paddingSizeLarge),
                child: Column(mainAxisSize: MainAxisSize.min, children: [

                  CustomAssetImageWidget(image: Images.deleteIcon, height: 50, width: 50),
                  const SizedBox(height: Dimensions.paddingSizeExtraLarge),

                  Text(
                    'delete_this_payment_method'.tr,
                    style: robotoMedium,
                  ),
                  const SizedBox(height: Dimensions.paddingSizeExtraSmall),

                  Text(
                    'once_delete_you_cannot_recover_this_information'.tr,
                    style: robotoRegular.copyWith(color: Theme.of(context).disabledColor, fontSize: Dimensions.fontSizeSmall),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Dimensions.paddingSizeExtraLarge),

                  Row(children: [
                    Expanded(
                      child: CustomButtonWidget(
                        buttonText: 'no'.tr,
                        backgroundColor: Theme.of(context).disabledColor.withValues(alpha: 0.1),
                        isBorder: true,
                        fontColor: Theme.of(context).hintColor,
                        onPressed: () => Get.back(),
                      ),
                    ),
                    const SizedBox(width: Dimensions.paddingSizeSmall),

                    Expanded(
                      child: CustomButtonWidget(
                        isLoading: disbursementController.isDeleteLoading,
                        buttonText: 'yes'.tr,
                        onPressed: () => disbursementController.deleteMethod(id),
                      ),
                    ),
                  ]),

                ]),
              ),
            ],
          ),
        ),
      );
    });
  }
}