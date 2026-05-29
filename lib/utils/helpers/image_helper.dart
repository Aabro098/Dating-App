import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:viora/Services/AppConfigService.dart';

class ReactiveProfileImage extends HookWidget {
  final String imagePath;
  final String gender;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxFit? fit;

  const ReactiveProfileImage({
    super.key,
    required this.imagePath,
    required this.gender,
    this.width,
    this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
  });

  Future<String?> _resolveImageUrl(String imagePath) async {
    if (imagePath.isEmpty) {
      return null;
    }

    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }

    if (imagePath.startsWith('gs://')) {
      final ref = FirebaseStorage.instance.refFromURL(imagePath);
      return await ref.getDownloadURL();
    }

    final baseUrl = AppConfigService.baseUrl.trim();
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final cleanPath = imagePath.startsWith('/')
        ? imagePath.substring(1)
        : imagePath;

    final fullPath = '$cleanBase/$cleanPath';

    if (fullPath.startsWith('gs://')) {
      final ref = FirebaseStorage.instance.refFromURL(fullPath);
      final response = await ref.getDownloadURL();
      return response;
    }

    if (fullPath.startsWith('http://') || fullPath.startsWith('https://')) {
      return fullPath;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final imageFuture = useMemoized(() => _resolveImageUrl(imagePath), [
      imagePath,
    ]);

    final snapshot = useFuture(imageFuture);

    Widget fallback() {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          fit: fit,
          alignment: Alignment.center,
          progressIndicatorBuilder: (context, url, downloadProgress) => Center(
            child: CircularProgressIndicator(value: downloadProgress.progress),
          ),
          imageUrl: gender.toLowerCase() == "female"
              ? AppConfigService.femaleImageUrl
              : AppConfigService.maleImageUrl,
          width: width ?? double.infinity,
          height: height ?? double.infinity,
        ),
      );
    }

    if (snapshot.connectionState == ConnectionState.waiting) {
      return Center(child: CircularProgressIndicator());
    }

    final resolvedUrl = snapshot.data;
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return fallback();
    }

    final image = CachedNetworkImage(
      memCacheWidth: (width?.isFinite ?? false) ? width!.toInt() : null,
      memCacheHeight: (height?.isFinite ?? false) ? height!.toInt() : null,
      imageUrl: resolvedUrl,
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      fit: BoxFit.cover,
      alignment: const Alignment(0.0, -1.0),
      progressIndicatorBuilder: (context, url, downloadProgress) =>
          Center(child: CircularProgressIndicator()),
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      errorWidget: (_, _, _) => fallback(),
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }

    return image;
  }
}
