import 'dart:io';
import 'package:path/path.dart' as Path;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/Services/ProgressBarHelper.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:overlay_support/overlay_support.dart';
import '../../constants.dart';
import '../../size_config.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

class MyPhotos extends StatefulWidget {
  static String routeName = "/myphotos";

  @override
  _MyPhotosState createState() => _MyPhotosState();
}

class _MyPhotosState extends State<MyPhotos> {
  late File _image;
  final picker = ImagePicker();
  late UserDetails user;
  late bool isLoading;

  Future<void> getUser() async {
    CollectionReference collectionReference = FirebaseFirestore.instance
        .collection("Users");

    collectionReference
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .snapshots()
        .listen((event) {
          user = UserDetails.fromJson(event.data() as Map<String, dynamic>);
          if (mounted) {
            setState(() {
              isLoading = false;
            });
          }
        });
  }

  void initState() {
    // TODO: implement initState
    super.initState();
    isLoading = true;
    getUser();
  }

  Future getImage() async {
    FirebaseStorage storage = FirebaseStorage.instance;
    ImageCropper imageCropper = ImageCropper();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    CroppedFile? croppedFile = await imageCropper.cropImage(
      sourcePath: pickedFile != null ? pickedFile.path : "",

      // aspectRatioPresets: [
      //   CropAspectRatioPreset.square,
      // ],
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Upload Image',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
        ),
        IOSUiSettings(minimumAspectRatio: 1.0),
      ],
    );
    setState(() {
      _image = croppedFile as File;
    });

    ProgressBarHelper.load(context);
    ProgressBarHelper.pr.show();
    Reference ref = storage
        .ref()
        .child(FirebaseAuth.instance.currentUser!.uid)
        .child(DateTime.now().toString());
    UploadTask uploadTask = ref.putFile(_image);

    await uploadTask.whenComplete(() async {
      String imgUrl = await ref.getDownloadURL();
      final storagePath = ref.fullPath;
      DatabaseService.updateField({
        "images": FieldValue.arrayUnion([imgUrl]),
        "imagePaths": FieldValue.arrayUnion([storagePath]),
      });
    });

    //  print("Photo Added");
    ProgressBarHelper.pr.hide();
    showSimpleNotification(
      Text("Photo Uploaded Successfully"),
      leading: Icon(Icons.done),
      position: NotificationPosition.bottom,
      background: Colors.green,
      duration: Duration(seconds: 2),
      slideDismiss: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),
        child:
            /// Custom Navigation Drawer and Search Button
            SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: kPrimaryColor,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                      },
                      child: Container(
                        height: 57.6,
                        width: 57.6,
                        padding: EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9.6),
                        ),
                        child: Icon(
                          Icons.arrow_back_ios,
                          color: Colors.white,
                          size: getProportionateScreenWidth(28),
                        ),
                      ),
                    ),
                    Spacer(flex: 1),
                    Text(
                      "My Photos",
                      style: TextStyle(
                        fontSize: getProportionateScreenWidth(20),
                        color: Colors.white,
                      ),
                    ),
                    Spacer(flex: 2),
                  ],
                ),
              ),
            ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : GridView.count(
              crossAxisCount: 2,
              padding: EdgeInsets.all(getProportionateScreenWidth(20)),
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              physics: ScrollPhysics(),
              scrollDirection: Axis.vertical,
              shrinkWrap: true,
              children: [
                GestureDetector(
                  onTap: () {
                    if (user.images!.length < 5) {
                      getImage();
                    } else {
                      showSimpleNotification(
                        Text("You can't Upload more than 5 Photos"),
                        background: Colors.redAccent,
                        position: NotificationPosition.bottom,
                      );
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      border: Border.all(color: kSecondaryColor, width: 2),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          size: getProportionateScreenHeight(40),
                        ),
                        Text("Add Photo", style: sHeadingStyle),
                      ],
                    ),
                  ),
                ),
                for (var image in user.images!) PhotoCard(image: image),
              ],
            ),
    );
  }
}

class PhotoCard extends StatelessWidget {
  String image;

  PhotoCard({required this.image});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            child: CachedNetworkImage(
              imageUrl: image,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              onTap: () async {
                var fileUrl = Uri.decodeFull(
                  Path.basename(image),
                ).replaceAll(new RegExp(r'(\?alt).*'), '');

                final Reference firebaseStorageRef = FirebaseStorage.instance
                    .ref()
                    .child(fileUrl);
                await firebaseStorageRef.delete();
                DatabaseService.updateField({
                  "images": FieldValue.arrayRemove([image]),
                });

                showSimpleNotification(
                  Text("Photo Deleted Successfully"),
                  leading: Icon(Icons.done),
                  position: NotificationPosition.bottom,
                  background: Colors.redAccent,
                  duration: Duration(seconds: 2),
                  slideDismiss: true,
                );
              },
              child: Icon(Icons.delete),
            ),
          ),
        ],
      ),
    );
  }
}
