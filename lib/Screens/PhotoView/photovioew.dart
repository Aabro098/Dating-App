import 'package:flutter/material.dart';
import 'package:viora/utils/helpers/image_helper.dart';

class PhotoView extends StatelessWidget {
  String image;
  PhotoView({super.key, required this.image});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: InteractiveViewer(
          child: ReactiveProfileImage(
            imagePath: image,
            gender: "male",
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
