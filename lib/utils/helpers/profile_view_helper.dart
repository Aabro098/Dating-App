import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:viora/Services/AppConfigService.dart';

class ReactiveProfileGallery extends HookWidget {
  final List<String> images;
  final String gender;
  final PageController? controller;
  final BorderRadius? borderRadius;
  final ValueChanged<int>? onPageChanged;
  final ValueNotifier<bool>? resetTrigger;
  final bool isImageTapped;
  final int currentPageIndex;

  const ReactiveProfileGallery({
    super.key,
    required this.images,
    required this.gender,
    this.controller,
    this.borderRadius,
    this.onPageChanged,
    this.resetTrigger,
    this.isImageTapped = false,
    this.currentPageIndex = 0,
  });

  Future<String?> _resolveImageUrl(String imagePath) async {
    if (imagePath.isEmpty) return null;

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
      return await ref.getDownloadURL();
    }

    if (fullPath.startsWith('http://') || fullPath.startsWith('https://')) {
      return fullPath;
    }

    return null;
  }

  Future<List<String>> _resolveAllImages() async {
    final fallback = gender.toLowerCase() == "female"
        ? AppConfigService.femaleImageUrl
        : AppConfigService.maleImageUrl;

    if (images.isEmpty) return [fallback];

    final resolved = await Future.wait(
      images.map((path) async {
        final url = await _resolveImageUrl(path.trim());
        return (url == null || url.isEmpty) ? fallback : url;
      }),
    );

    return resolved;
  }

  @override
  Widget build(BuildContext context) {
    final future = useMemoized(_resolveAllImages, [images, gender]);
    final snapshot = useFuture(future);

    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    final resolvedImages = snapshot.data ?? [];
    if (resolvedImages.isEmpty) {
      return const SizedBox.shrink();
    }

    final photoControllers = useMemoized(
      () => List.generate(resolvedImages.length, (_) => PhotoViewController()),
      [resolvedImages.length],
    );

    final scaleStateControllers = useMemoized(
      () => List.generate(
        resolvedImages.length,
        (_) => PhotoViewScaleStateController(),
      ),
      [resolvedImages.length],
    );

    useEffect(() {
      final subscriptions = <StreamSubscription>[];

      for (int i = 0; i < scaleStateControllers.length; i++) {
        final sub = scaleStateControllers[i].outputScaleStateStream.listen((
          state,
        ) {
          if (state == PhotoViewScaleState.initial) {
            photoControllers[i].updateMultiple(
              position: Offset.zero,
              rotation: 0.0,
            );
          }
        });

        subscriptions.add(sub);
      }

      return () {
        for (final sub in subscriptions) {
          sub.cancel();
        }
        for (final controller in photoControllers) {
          controller.dispose();
        }
        for (final controller in scaleStateControllers) {
          controller.dispose();
        }
      };
    }, [scaleStateControllers, photoControllers]);

    useEffect(() {
      void listener() {
        if (resetTrigger?.value == true) {
          final currentPage = controller?.page?.round() ?? 0;

          // Force position to center first
          photoControllers[currentPage].updateMultiple(
            position: Offset.zero,
            rotation: 0.0,
          );

          // Then reset scale state
          WidgetsBinding.instance.addPostFrameCallback((_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              photoControllers[currentPage].updateMultiple(
                position: Offset.zero,
                rotation: 0.0,
              );
              // Reset position AGAIN after scale settles
              scaleStateControllers[currentPage].scaleState =
                  PhotoViewScaleState.initial;

              resetTrigger!.value = false;
            });
          });
        }
      }

      resetTrigger?.addListener(listener);
      return () => resetTrigger?.removeListener(listener);
    }, [resetTrigger]);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (controller != null && controller!.hasClients) {
          final safeIndex = currentPageIndex.clamp(
            0,
            resolvedImages.length - 1,
          );
          controller!.jumpToPage(safeIndex);
        }
      });

      return null;
    }, [isImageTapped]);

    Widget gallery;

    if (isImageTapped) {
      gallery = PhotoViewGallery.builder(
        pageController: controller,
        itemCount: resolvedImages.length,
        onPageChanged: onPageChanged,
        backgroundDecoration: const BoxDecoration(color: Colors.transparent),
        builder: (context, index) {
          final imageUrl = resolvedImages[index];
          return PhotoViewGalleryPageOptions(
            basePosition: const Alignment(0.0, -1.0),
            imageProvider: CachedNetworkImageProvider(imageUrl),
            controller: photoControllers[index],
            scaleStateController: scaleStateControllers[index],
            minScale: PhotoViewComputedScale.covered,
            initialScale: PhotoViewComputedScale.covered,
            maxScale: PhotoViewComputedScale.covered * 1.1,

            tightMode: true,
            heroAttributes: PhotoViewHeroAttributes(tag: '$imageUrl-$index'),
          );
        },
        loadingBuilder: (context, event) =>
            const Center(child: CircularProgressIndicator()),
      );
    } else {
      gallery = PageView.builder(
        controller: controller,
        itemCount: resolvedImages.length,
        onPageChanged: onPageChanged,
        physics: const PageScrollPhysics(),
        itemBuilder: (context, index) {
          final imageUrl = resolvedImages[index];

          return CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            alignment: const Alignment(0.0, -1.0),
            placeholder: (context, url) => Container(color: Colors.grey[300]),
            errorWidget: (context, url, error) =>
                Container(color: Colors.grey[300]),
          );
        },
      );
    }

    if (borderRadius != null) {
      gallery = ClipRRect(borderRadius: borderRadius!, child: gallery);
    }

    return gallery;
  }
}
