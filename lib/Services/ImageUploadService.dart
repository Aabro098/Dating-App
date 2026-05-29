import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:viora/Services/AppConfigService.dart';
import 'package:viora/Services/ProgressBarHelper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:viora/Services/UserProvider.dart';
import 'package:viora/Services/image_analyzer.dart';
import 'package:viora/models/Message.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:provider/provider.dart';
import 'package:viora/models/SupportModels.dart';
import 'package:viora/models/UserDetails.dart';

import 'ChatService.dart';
import 'NotificationService.dart';

// Helper for conditional logging
void _log(String message) {
  if (kDebugMode) {
    print(message);
  }
}

class ImageUploadService {
  // static Future<void> printStoredImageRefsForCurrentUser() async {
  //   try {
  //     final user = FirebaseAuth.instance.currentUser;
  //     if (user == null) {
  //       _log('[ImageUploadService] No authenticated user for Firestore print.');
  //       return;
  //     }

  //     final doc = await FirebaseFirestore.instance
  //         .collection('Users')
  //         .doc(user.uid)
  //         .get();

  //     if (!doc.exists) {
  //       _log('[ImageUploadService] User doc not found: ${user.uid}');
  //       return;
  //     }

  //     final data = doc.data() ?? <String, dynamic>{};
  //     final images = (data['images'] as List?)?.cast<String>() ?? <String>[];
  //     final imagePaths =
  //         (data['imagePaths'] as List?)?.cast<String>() ?? <String>[];

  //     _log('[ImageUploadService] Firestore images (urls): $images');
  //     _log('[ImageUploadService] Firestore imagePaths (relative): $imagePaths');
  //     _log(
  //       '[ImageUploadService] Firestore verifiedImageUrl: ${data['verifiedImageUrl']}',
  //     );
  //     _log(
  //       '[ImageUploadService] Firestore verifiedImagePath: ${data['verifiedImagePath']}',
  //     );
  //   } catch (e) {
  //     _log('[ImageUploadService] Failed to print stored refs: $e');
  //   }
  // }

  // static Future<MessageValidationResult> _processImage(String imagePath) async {
  //   // final inputImage = InputImage.fromFilePath(imagePath);
  //   // final textRecognizer = TextRecognizer();
  //   final RecognizedText recognizedText =
  //       await OCRImageProcessor.recognizeTextFromImage(imagePath);

  //   for (TextBlock block in recognizedText.blocks) {
  //     final List<TextLine> textLine = block.lines;

  //     for (TextLine textLine in block.lines) {
  //       final messageValidator = MessageValidator.validateMessage(
  //         textLine.text,
  //       );
  //       _log("Recognized text in image: ${textLine.text}");
  //       if (messageValidator.isValid == false) {
  //         _log("Invalid text found in image: ${textLine.text}");
  //         return messageValidator;
  //       }
  //     }

  //     _log("TextLine list length: ${textLine.length}");
  //     // debugPrint("vinayImage this is the recognized text in the image : ${block.text.length}");
  //     return MessageValidationResult(isValid: true, reason: '');
  //   }
  //   String extractedText = recognizedText.text;
  //   final isImageValid = MessageValidator.validateMessage(extractedText);
  //   return isImageValid;
  // }

  static Future getImageForMyProfile(BuildContext context) async {
    final picker = ImagePicker();
    final FirebaseStorage storage = FirebaseStorage.instance;
    final ImageCropper imageCropper = ImageCropper();

    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );

    if (pickedFile == null) {
      // showSimpleNotification(
      //   const Text("Something went wrong!! Please try again"),
      //   leading: const Icon(Icons.done),
      //   position: NotificationPosition.bottom,
      //   background: Colors.red,
      //   duration: const Duration(seconds: 2),
      //   slideDismissDirection: DismissDirection.horizontal,
      // );
      return;
    }

    CroppedFile? croppedFile = await imageCropper.cropImage(
      sourcePath: pickedFile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Upload Image',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: false,
        ),
        IOSUiSettings(minimumAspectRatio: 1.0),
      ],
    );

    if (croppedFile == null) {
      // showSimpleNotification(
      //   const Text("Image crop cancelled"),
      //   leading: const Icon(Icons.cancel),
      //   position: NotificationPosition.bottom,
      //   background: Colors.orange,
      //   duration: const Duration(seconds: 2),
      //   slideDismissDirection: DismissDirection.horizontal,
      // );
      return;
    }

    final File image = File(croppedFile.path);

    try {
      final result = await VisionNsfwService().analyzeSingle(image);

      if (!result.accepted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.reason), backgroundColor: Colors.red),
        );
        return; // reject here
      }

      ProgressBarHelper.load(context);
      ProgressBarHelper.pr.show();

      final currentUid = FirebaseAuth.instance.currentUser!.uid;
      // keep extension
      final originalName = image.path.split('/').last;
      final ext = originalName.contains('.')
          ? originalName.split('.').last
          : 'jpg';

      // store in profileImages folder
      final ref = storage
          .ref()
          .child('profileImages')
          .child(currentUid)
          .child('${DateTime.now().millisecondsSinceEpoch}.$ext');

      final uploadTask = ref.putFile(image);

      await uploadTask.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw TimeoutException('Image upload timed out after 60 seconds');
        },
      );

      // DO NOT call getDownloadURL() here
      // Store only the Firebase Storage path
      final storagePath = ref.fullPath;

      DatabaseService.updateField({
        // remove this if you do not want https:// urls stored anymore
        // "images": FieldValue.arrayUnion([imgUrl]),
        "imagePaths": FieldValue.arrayUnion([storagePath]),
      });

      await Future<void>.delayed(const Duration(milliseconds: 500));
      // await printStoredImageRefsForCurrentUser();

      ProgressBarHelper.pr.hide();

      showSimpleNotification(
        const Text("Photo Uploaded Successfully"),
        leading: const Icon(Icons.done),
        position: NotificationPosition.bottom,
        background: Colors.green,
        duration: const Duration(seconds: 2),

        slideDismissDirection: DismissDirection.horizontal,
      );
    } catch (e) {
      ProgressBarHelper.pr.hide();
      debugPrint("Error uploading profile image: $e");

      showSimpleNotification(
        const Text("Upload failed. Please try again."),
        leading: const Icon(Icons.cancel_rounded),
        position: NotificationPosition.bottom,
        background: Colors.red,
        duration: const Duration(seconds: 2),
        slideDismissDirection: DismissDirection.horizontal,
      );
    }
  }

  static Future getBotImage(BuildContext context, botId) async {
    final picker = ImagePicker();
    final FirebaseStorage storage = FirebaseStorage.instance;
    final ImageCropper imageCropper = ImageCropper();

    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );

    if (pickedFile == null) {
      // showSimpleNotification(
      //   const Text("Something went wrong!! Please try again"),
      //   leading: const Icon(Icons.done),
      //   position: NotificationPosition.bottom,
      //   background: Colors.red,
      //   duration: const Duration(seconds: 2),
      //   slideDismissDirection: DismissDirection.horizontal,
      // );
      return;
    }

    CroppedFile? croppedFile = await imageCropper.cropImage(
      sourcePath: pickedFile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Upload Image',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: false,
        ),
        IOSUiSettings(minimumAspectRatio: 1.0),
      ],
    );

    if (croppedFile == null) {
      // showSimpleNotification(
      //   const Text("Image crop cancelled"),
      //   leading: const Icon(Icons.cancel),
      //   position: NotificationPosition.bottom,
      //   background: Colors.orange,
      //   duration: const Duration(seconds: 2),
      //   slideDismissDirection: DismissDirection.horizontal,
      // );
      return;
    }

    final File image = File(croppedFile.path);

    try {
      ProgressBarHelper.load(context);
      ProgressBarHelper.pr.show();

      // keep extension
      final originalName = image.path.split('/').last;
      final ext = originalName.contains('.')
          ? originalName.split('.').last
          : 'jpg';

      // store with botId instead of currentUid
      final ref = storage
          .ref()
          .child('profileImages')
          .child(botId)
          .child('${DateTime.now().millisecondsSinceEpoch}.$ext');

      final uploadTask = ref.putFile(image);

      await uploadTask.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw TimeoutException('Image upload timed out after 60 seconds');
        },
      );

      // DO NOT call getDownloadURL() here
      // Store only the Firebase Storage path
      final storagePath = ref.fullPath;

      DatabaseService.updateUserField(botId, {
        "imagePaths": FieldValue.arrayUnion([storagePath]),
      });

      ProgressBarHelper.pr.hide();

      showSimpleNotification(
        const Text("Photo Uploaded Successfully"),
        leading: const Icon(Icons.done),
        position: NotificationPosition.bottom,
        background: Colors.green,
        duration: const Duration(seconds: 2),
        slideDismissDirection: DismissDirection.horizontal,
      );
    } catch (e) {
      ProgressBarHelper.pr.hide();
      debugPrint("Error uploading bot image: $e");

      showSimpleNotification(
        const Text("Upload failed. Please try again."),
        leading: const Icon(Icons.cancel_rounded),
        position: NotificationPosition.bottom,
        background: Colors.red,
        duration: const Duration(seconds: 2),
        slideDismissDirection: DismissDirection.horizontal,
      );
    }
  }

  // static Future sendImageMessage(context, roomId, user) async {
  //   File _image;
  //   final picker = ImagePicker();
  //   FirebaseStorage storage = FirebaseStorage.instance;
  //   ImageCropper imageCropper = ImageCropper();

  //   final pickedFile = await picker.pickImage(
  //     source: ImageSource.gallery,
  //     imageQuality: 50,
  //   );
  //   CroppedFile? croppedFile = await imageCropper.cropImage(
  //     sourcePath: pickedFile != null ? pickedFile.path : '',
  //     // aspectRatioPresets: [CropAspectRatioPreset.square],
  //     uiSettings: [
  //       AndroidUiSettings(
  //         toolbarTitle: 'Send Image',
  //         toolbarColor: Colors.black,
  //         toolbarWidgetColor: Colors.white,
  //         initAspectRatio: CropAspectRatioPreset.square,
  //         lockAspectRatio: true,
  //       ),
  //       IOSUiSettings(minimumAspectRatio: 1.0),
  //     ],
  //   );

  //   if (croppedFile != null) {
  //     _image = File(croppedFile.path);
  //     //unused library code for ml kit
  //     // final isImageValid = await _processImage(_image.path);
  //     // Future.delayed(Duration(seconds: 3));
  //     // if (isImageValid.isValid == true) {
  //     ProgressBarHelper.load(context);
  //     ProgressBarHelper.pr.show();
  //     Reference ref = storage
  //         .ref()
  //         .child(FirebaseAuth.instance.currentUser!.uid)
  //         .child(DateTime.now().toString());
  //     UploadTask uploadTask = ref.putFile(_image);

  //     await uploadTask.whenComplete(() async {
  //       String imgUrl = await ref.getDownloadURL();
  //       final storagePath = ref.fullPath;
  //       debugPrint('vinay i am the imgUrl $imgUrl');
  //       MessageModel message = MessageModel(
  //         seen: false,
  //         date: DateTime.now(),
  //         uid: FirebaseAuth.instance.currentUser!.uid,
  //         text: imgUrl,
  //         imagePath: [storagePath],
  //         receiver: user.uid,

  //         roomId: roomId,
  //       );
  //       ChatService.sendMessage(message, context);
  //       NotificationService.sendNotification(
  //         user.fcmToken,
  //         "Message from ${Provider.of<UserProvider>(context, listen: false).userDetails.name}",
  //         "Image",
  //         user.fcmToken == 'Admin'
  //             ? user.uid
  //             : FirebaseAuth.instance.currentUser!.uid,
  //       );
  //     });
  //     ProgressBarHelper.pr.hide();
  //   }
  //   // else {
  //   //     print("vinayImage the image was rejected");
  //   //     showSimpleNotification(
  //   //       Text("Please Don't Put Any Contact Info On Photo"),
  //   //       leading: Icon(Icons.cancel_rounded),
  //   //       position: NotificationPosition.bottom,
  //   //       background: Colors.red,
  //   //       duration: Duration(seconds: 2),
  //   //       slideDismiss: true,
  //   //     );
  //   //   }
  //   // }
  // }

  static Future sendMultipleImageMessage(
    BuildContext context,
    String roomId,
    dynamic user,
    int coins,
    bool isFemale,
  ) async {
    final picker = ImagePicker();
    final FirebaseStorage storage = FirebaseStorage.instance;
    final ImageCropper imageCropper = ImageCropper();

    final int imageSendLimit = AppConfigService.imageSendLimit;

    final int limit = coins == -1
        ? imageSendLimit
        : math.min(coins, imageSendLimit);
    List<XFile> pickedFiles = [];

    if (limit == 1) {
      final pickedFile = await picker.pickImage(
        imageQuality: 50,
        source: ImageSource.gallery,
      );
      if (pickedFile != null) {
        pickedFiles = [pickedFile];
      }
    } else {
      pickedFiles = await picker.pickMultiImage(imageQuality: 50, limit: limit);
    }

    if (pickedFiles.isEmpty) return;

    if (pickedFiles.length > limit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("You can only send $limit image(s)"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Crop all picked images
    List<CroppedFile?> croppedFiles = [];
    for (var pickedFile in pickedFiles) {
      final croppedFile = await imageCropper.cropImage(
        sourcePath: pickedFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: false,
          ),
          IOSUiSettings(minimumAspectRatio: 1.0),
        ],
      );
      croppedFiles.add(croppedFile);
    }

    // Filter out cancelled crops
    final validCroppedFiles = croppedFiles
        .where((f) => f != null)
        .cast<CroppedFile>()
        .toList();

    if (validCroppedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("All images were cancelled"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final files = validCroppedFiles.map((e) => File(e.path)).toList();

    ProgressBarHelper.load(context);
    ProgressBarHelper.pr.show();

    List<File> validImages = [];
    List<String> rejectedReasons = [];

    try {
      if (imageSendLimit > 0) {
        final results = await VisionNsfwService().analyzeImages(files);

        for (int i = 0; i < files.length; i++) {
          final result = results[i];

          if (result.accepted) {
            validImages.add(files[i]);
          } else {
            rejectedReasons.add(result.reason);
          }
        }
      } else {
        validImages = files;
      }

      if (validImages.isEmpty) {
        ProgressBarHelper.pr.hide();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("All selected images were rejected"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (validImages.length > limit) {
        ProgressBarHelper.pr.hide();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Cannot send ${validImages.length} images. Limit is $limit image(s)",
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
      final currentUid = FirebaseAuth.instance.currentUser!.uid;

      final uploadFutures = validImages.asMap().entries.map((entry) async {
        final index = entry.key;
        final image = entry.value;

        // Keep file extension if possible
        final originalName = image.path.split('/').last;
        final ext = originalName.contains('.')
            ? originalName.split('.').last
            : 'jpg';

        // Store inside chatImages folder
        final ref = storage
            .ref()
            .child('chatImages')
            .child(currentUid)
            .child(roomId)
            .child('${baseTimestamp}_$index.$ext');

        await ref.putFile(image);

        // IMPORTANT:
        // Send/store only the Firebase Storage path
        // Example: chatImages/uid/roomId/1712345678_0.jpg
        return ref.fullPath;
      }).toList();

      final imagePaths = await Future.wait(uploadFutures);

      final message = MessageModel(
        seen: false,
        date: DateTime.now(),
        uid: currentUid,
        text: "vioraa.firebasestorage.app",
        imagePath: imagePaths, // now contains storage paths, not download URLs
        receiver: user.uid,
        roomId: roomId,
      );

      ChatService.sendMessage(message, context);

      NotificationService.sendNotification(
        user.fcmToken,
        "Message from ${Provider.of<UserProvider>(context, listen: false).userDetails.name}",
        "Images",
        user.fcmToken == 'Admin' ? user.uid : currentUid,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to send images"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      ProgressBarHelper.pr.hide();
    }
  }

  static Future sendMultipleSupportImages(
    BuildContext context,
    String roomId,
    UserDetails user,
    String? categoryId,
    String? questionId,
  ) async {
    final picker = ImagePicker();
    FirebaseStorage storage = FirebaseStorage.instance;
    final ImageCropper imageCropper = ImageCropper();

    List<XFile> pickedFiles = [];

    pickedFiles = await picker.pickMultiImage(imageQuality: 50);

    if (pickedFiles.isEmpty) return;

    // Crop all picked images
    List<CroppedFile?> croppedFiles = [];
    for (var pickedFile in pickedFiles) {
      final croppedFile = await imageCropper.cropImage(
        sourcePath: pickedFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: false,
          ),
          IOSUiSettings(minimumAspectRatio: 1.0),
        ],
      );
      croppedFiles.add(croppedFile);
    }

    // Filter out cancelled crops
    final validCroppedFiles = croppedFiles
        .where((f) => f != null)
        .cast<CroppedFile>()
        .toList();

    if (validCroppedFiles.isEmpty) return;

    final files = validCroppedFiles.map((e) => File(e.path)).toList();

    ProgressBarHelper.load(context);
    ProgressBarHelper.pr.show();

    try {
      // Upload all images in parallel
      final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
      final currentUid = FirebaseAuth.instance.currentUser!.uid;
      final uploadFutures = files.asMap().entries.map((entry) async {
        final index = entry.key;
        final image = entry.value;

        // Keep file extension if possible
        final originalName = image.path.split('/').last;
        final ext = originalName.contains('.')
            ? originalName.split('.').last
            : 'jpg';

        // ✅ Each image gets unique filename: timestamp_index
        final ref = storage
            .ref()
            .child('chatImages')
            .child(currentUid)
            .child(roomId)
            .child('${baseTimestamp}_$index.$ext');

        try {
          await ref.putFile(image);
          final storagePath = ref.fullPath;
          _log('Image $index uploaded successfully: $storagePath');
          return storagePath;
        } catch (e) {
          _log('Error uploading image $index: $e');
          rethrow;
        }
      }).toList();

      final imageUrls = await Future.wait(uploadFutures);

      // 5. Send message with array of images
      SupportMessageModel message = SupportMessageModel(
        seen: false,
        date: DateTime.now(),
        uid: FirebaseAuth.instance.currentUser!.uid,
        text: "vioraa.firebasestorage.app", // no text
        imageUrls: imageUrls, // <-- LIST<String>
        roomId: roomId,
        categoryId: categoryId,
        questionId: questionId,
        messageType: 'user',
      );

      ChatService.sendSupportMessageEnhanced(message, context);

      NotificationService.sendNotification(
        user.fcmToken,
        "Message from ${Provider.of<UserProvider>(context, listen: false).userDetails.name}",
        "Images",
        user.fcmToken == 'Admin'
            ? user.uid
            : FirebaseAuth.instance.currentUser!.uid,
      );
    } catch (e) {
      debugPrint("Error: $e");
    }
    ProgressBarHelper.pr.hide();
  }

  static Future sendMultipleSupportImagesAdmin(
    BuildContext context,
    String roomId,
    UserDetails user,
  ) async {
    final picker = ImagePicker();
    FirebaseStorage storage = FirebaseStorage.instance;
    final ImageCropper imageCropper = ImageCropper();

    List<XFile> pickedFiles = [];

    pickedFiles = await picker.pickMultiImage(imageQuality: 50);

    if (pickedFiles.isEmpty) return;

    // Crop all picked images
    List<CroppedFile?> croppedFiles = [];
    for (var pickedFile in pickedFiles) {
      final croppedFile = await imageCropper.cropImage(
        sourcePath: pickedFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: false,
          ),
          IOSUiSettings(minimumAspectRatio: 1.0),
        ],
      );
      croppedFiles.add(croppedFile);
    }

    // Filter out cancelled crops
    final validCroppedFiles = croppedFiles
        .where((f) => f != null)
        .cast<CroppedFile>()
        .toList();

    if (validCroppedFiles.isEmpty) return;

    final files = validCroppedFiles.map((e) => File(e.path)).toList();

    ProgressBarHelper.load(context);
    ProgressBarHelper.pr.show();

    try {
      // Upload all images in parallel
      final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
      final uploadFutures = files.asMap().entries.map((entry) async {
        final index = entry.key;
        final image = entry.value;

        // Keep file extension if possible
        final originalName = image.path.split('/').last;
        final ext = originalName.contains('.')
            ? originalName.split('.').last
            : 'jpg';

        // ✅ Each image gets unique filename: timestamp_index
        final ref = storage
            .ref()
            .child('chatImages')
            .child(user.uid)
            .child(roomId)
            .child('${baseTimestamp}_$index.$ext');

        try {
          await ref.putFile(image);
          final storagePath = ref.fullPath;
          _log('Image $index uploaded successfully: $storagePath');
          return storagePath;
        } catch (e) {
          _log('Error uploading image $index: $e');
          rethrow;
        }
      }).toList();

      final imageUrls = await Future.wait(uploadFutures);

      // 5. Send message with array of images
      SupportMessageModel message = SupportMessageModel(
        seen: false,
        date: DateTime.now(),
        uid: "support",
        text: "vioraa.firebasestorage.app", // no text
        imageUrls: imageUrls, // <-- LIST<String>
        roomId: roomId,
      );

      ChatService.sendSupportMessageEnhanced(message, context);

      NotificationService.sendNotification(
        user.fcmToken,
        "Message for ${Provider.of<UserProvider>(context, listen: false).userDetails.name}",
        "Images",
        user.fcmToken == 'Admin'
            ? user.uid
            : FirebaseAuth.instance.currentUser!.uid,
      );
    } catch (e) {
      debugPrint("Error: $e");
    }

    ProgressBarHelper.pr.hide();
  }

  static Future sendBotImageMessage(
    BuildContext context,
    message,
    bot,
    fcmToken,
    roomId,
  ) async {
    try {
      final picker = ImagePicker();
      final FirebaseStorage storage = FirebaseStorage.instance;
      final ImageCropper imageCropper = ImageCropper();

      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 50,
      );

      if (pickedFile == null) {
        // showSimpleNotification(
        //   const Text("Something went wrong!! Please try again"),
        //   leading: const Icon(Icons.done),
        //   position: NotificationPosition.bottom,
        //   background: Colors.red,
        //   duration: const Duration(seconds: 2),
        //   slideDismissDirection: DismissDirection.horizontal,
        // );
        return;
      }

      CroppedFile? croppedFile = await imageCropper.cropImage(
        sourcePath: pickedFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Send Image',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
          ),
          IOSUiSettings(minimumAspectRatio: 1.0),
        ],
      );

      if (croppedFile == null) {
        // showSimpleNotification(
        //   const Text("Image crop cancelled"),
        //   leading: const Icon(Icons.cancel),
        //   position: NotificationPosition.bottom,
        //   background: Colors.orange,
        //   duration: const Duration(seconds: 2),
        //   slideDismissDirection: DismissDirection.horizontal,
        // );
        return;
      }

      final File image = File(croppedFile.path);

      ProgressBarHelper.load(context);
      ProgressBarHelper.pr.show();

      // keep extension
      final originalName = image.path.split('/').last;
      final ext = originalName.contains('.')
          ? originalName.split('.').last
          : 'jpg';

      // Store inside chatImages folder with bot ID
      final ref = storage
          .ref()
          .child('chatImages')
          .child(bot.uid)
          .child(roomId)
          .child('${DateTime.now().millisecondsSinceEpoch}.$ext');

      final uploadTask = ref.putFile(image);

      await uploadTask.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw TimeoutException('Image upload timed out after 60 seconds');
        },
      );

      // Store only the Firebase Storage path, not the download URL
      final storagePath = ref.fullPath;

      message.text = "vioraa.firebasestorage.app";
      message.imagePath = [storagePath]; // Store storage path only
      ChatService.sendBotMessage(message);

      NotificationService.sendNotification(
        fcmToken,
        "Message from " + bot.name,
        "Image",
        bot.uid,
      );

      ProgressBarHelper.pr.hide();

      showSimpleNotification(
        const Text("Photo Sent Successfully"),
        leading: const Icon(Icons.done),
        position: NotificationPosition.bottom,
        background: Colors.green,
        duration: const Duration(seconds: 2),
        slideDismissDirection: DismissDirection.horizontal,
      );
    } catch (e) {
      ProgressBarHelper.pr.hide();
      debugPrint("Error sending bot image: $e");

      showSimpleNotification(
        const Text("Failed to send image. Please try again."),
        leading: const Icon(Icons.cancel_rounded),
        position: NotificationPosition.bottom,
        background: Colors.red,
        duration: const Duration(seconds: 2),
        slideDismissDirection: DismissDirection.horizontal,
      );
    }
  }
}
