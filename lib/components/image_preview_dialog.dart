import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:viora/Services/profile_business_logic.dart';
import 'package:viora/constants.dart';
import 'package:viora/utils/constatnts/colors.dart';
import 'package:viora/utils/helpers/image_helper.dart';
import '../size_config.dart';

class ImagePreviewDialog extends HookWidget {
  final String imageUrl;
  final List<String> userImages;
  const ImagePreviewDialog({
    required this.imageUrl,
    required this.userImages,
    super.key,
  });

  static Future<void> show(
    BuildContext context, {
    String? imageUrl,
    List<String>? userImages,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha(72),
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(
              horizontal: getProportionateScreenWidth(10),
              vertical: getProportionateScreenHeight(50),
            ),
            child: ImagePreviewDialog(
              imageUrl: imageUrl ?? "",
              userImages: userImages ?? [],
            ), // Pass userImages to the dialog
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = useState(true);

    useEffect(() {
      // Set loading to false after widget builds
      isLoading.value = false;
      return null;
    }, []);

    if (isLoading.value) {
      return Container(
        decoration: BoxDecoration(
          color: kBackgroundBG,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: EdgeInsets.all(getProportionateScreenWidth(40)),
        child: const Center(
          child: CircularProgressIndicator(color: kTertiaryPink),
        ),
      );
    }

    return _buildDialog(context);
  }

  Widget _buildDialog(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: getProportionateScreenHeight(525),
          maxWidth: getProportionateScreenWidth(352),
        ),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Close button
            Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: EdgeInsets.all(getProportionateScreenWidth(6)),
                  decoration: BoxDecoration(
                    color: AppColors.purple,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
            SizedBox(height: getProportionateScreenHeight(8)),
            // Image preview
            Flexible(
              child: imageUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        children: [
                          ReactiveProfileImage(
                            imagePath: imageUrl,
                            gender: "male",
                            height: getProportionateScreenHeight(525),
                            width: getProportionateScreenWidth(352),
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: GestureDetector(
                              onTap: () async {
                                Navigator.pop(context);
                                // Delegate to business logic
                                await ProfileBusinessLogic.setAsProfilePicture(
                                  imageUrl,
                                  userImages,
                                );
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: getProportionateScreenWidth(8),
                                  vertical: getProportionateScreenHeight(4),
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.purple,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  "Make Profile Picture",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: getProportionateScreenWidth(12),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      color: Colors.grey[200],
                      child: Icon(Icons.image, color: Colors.grey),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
