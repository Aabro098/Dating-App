import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/Services/ImageUploadService.dart';
import 'package:viora/components/customAppBar.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:viora/size_config.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:path/path.dart' as Path;
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:viora/utils/helpers/image_helper.dart';

import '../../constants.dart';
import 'EditBotProfile.dart';

class BotProfile extends StatefulWidget {
  String botId;
  BotProfile({required this.botId});
  @override
  _BotProfileState createState() => _BotProfileState();
}

class _BotProfileState extends State<BotProfile> {
  late bool isLoading;
  late UserDetails user;

  CollectionReference collectionReference = FirebaseFirestore.instance
      .collection("Users");

  Future<void> load() async {
    collectionReference.doc(widget.botId).snapshots().listen((value) {
      user = UserDetails.fromJson(value.data() as Map<String, dynamic>);
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    });
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    isLoading = true;
    load();
  }

  final tStyle = TextStyle(
    fontSize: getProportionateScreenWidth(14),
    fontWeight: FontWeight.bold,
    color: Colors.black,
    // height: 1.5,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),

        child: CustomAppBar(title: "Bot Profile"),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(50),
                                  ),
                                  child: ReactiveProfileImage(
                                    imagePath: user.images?.isNotEmpty == true
                                        ? user.images![0]
                                        : '',
                                    gender: user.gender ?? 'male',
                                    height: getProportionateScreenWidth(100),
                                    width: getProportionateScreenWidth(100),
                                  ),
                                  // child: CachedNetworkImage(
                                  //   imageUrl: user.images!.isEmpty
                                  //       ? user.gender == "Male"
                                  //             ? kMaleUrl
                                  //             : kFemaleUrl
                                  //       : user.images![0],
                                  //   height: getProportionateScreenWidth(100),
                                  //   width: getProportionateScreenWidth(100),
                                  // ),
                                ),
                              ),
                              Text(user.name!, style: sHeadingStyle),
                              Container(
                                padding: EdgeInsets.all(
                                  getProportionateScreenHeight(10),
                                ),
                                child: SvgPicture.asset(
                                  user.gender == "Female"
                                      ? "assets/svg/female.svg"
                                      : "assets/svg/male.svg",
                                  height: getProportionateScreenHeight(24),
                                ),
                              ),
                              Text("${user.age} Yrs"),
                              Text("${user.city!}/ ${user.state}"),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTap: () {
                                DatabaseService.updateUserField(user.uid, {
                                  "isOnline": !(user.isOnline == true
                                      ? true
                                      : false),
                                  "lastOnline": DateTime.now(),
                                });
                              },
                              child: Container(
                                margin: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.40),
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(10),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      (user.isOnline == true ? true : false)
                                          ? Text(
                                              "Online",
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            )
                                          : Text(
                                              "Offline ",
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                      Icon(
                                        Icons.circle,
                                        color:
                                            (user.isOnline == true
                                                ? true
                                                : false)
                                            ? Colors.green
                                            : Colors.deepOrangeAccent,
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 10),
                            GestureDetector(
                              onTap: () {
                                showCupertinoModalPopup<void>(
                                  context: context,
                                  builder: (BuildContext context) =>
                                      CupertinoActionSheet(
                                        title: Text(
                                          (user.isDisabled == true
                                                  ? true
                                                  : false)
                                              ? "Enable User"
                                              : "Disable User",
                                        ),
                                        message: Text(
                                          "This is for bot visibility",
                                        ),
                                        actions: <CupertinoActionSheetAction>[
                                          CupertinoActionSheetAction(
                                            onPressed: () async {
                                              DatabaseService.updateUserField(
                                                user.uid,
                                                {
                                                  "isDisabled":
                                                      !(user.isDisabled == true
                                                          ? true
                                                          : false),
                                                },
                                              );

                                              Navigator.pop(context);
                                              showSimpleNotification(
                                                Text("Bot Visibility updated"),
                                                background: Colors.green,
                                                duration: Duration(seconds: 3),
                                                position:
                                                    NotificationPosition.bottom,
                                                slideDismiss: true,
                                                leading: Icon(Icons.verified),
                                              );
                                            },
                                            isDestructiveAction:
                                                (user.isDisabled == true
                                                    ? true
                                                    : false)
                                                ? false
                                                : true,
                                            child: Text(
                                              (user.isDisabled == true
                                                      ? true
                                                      : false)
                                                  ? "Enable User"
                                                  : "Disable User",
                                            ),
                                          ),
                                        ],
                                        cancelButton:
                                            CupertinoActionSheetAction(
                                              onPressed: () async {
                                                Navigator.pop(context);
                                              },
                                              child: Text("Cancel"),
                                            ),
                                      ),
                                );
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: kPrimaryColor,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      "Visibility",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: getProportionateScreenWidth(
                                          16,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      (user.isDisabled == true ? true : false)
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: Colors.white,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                    Row(
                      children: [
                        Spacer(),
                        GestureDetector(
                          onTap: () {
                            //Navigator.pushNamed(context, EditProfile.routeName);
                            PersistentNavBarNavigator.pushNewScreen(
                              context,
                              screen: EditBotProfile(botId: widget.botId),
                              withNavBar:
                                  false, // OPTIONAL VALUE. True by default.
                              pageTransitionAnimation:
                                  PageTransitionAnimation.cupertino,
                            );
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: kPrimaryColor,
                              borderRadius: BorderRadius.all(
                                Radius.circular(12),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  "Edit",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: getProportionateScreenWidth(16),
                                  ),
                                ),
                                Icon(Icons.edit, color: Colors.white),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Sexual Orientation", style: tStyle),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: (user.sexualOrientation ?? [])
                                  .map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                      ),
                                      child: Chip(label: Text(item)),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Marital Status", style: tStyle),
                            Wrap(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  child: Chip(
                                    label: Text(user.maritalStatus ?? ""),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            user.relTypes!.length > 0
                                ? Text(
                                    "Types of Relationship looking for",
                                    style: tStyle,
                                  )
                                : SizedBox(),
                            Wrap(
                              direction: Axis.horizontal,
                              children: [
                                for (var i in user.relTypes!)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    child: Chip(label: Text(i)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Text("Photos", style: tStyle),
                              Spacer(),
                              GestureDetector(
                                onTap: () {
                                  if (user.images!.length < 5) {
                                    ImageUploadService.getBotImage(
                                      context,
                                      widget.botId,
                                    );
                                  } else {
                                    showSimpleNotification(
                                      Text(
                                        "You can't Upload more than 5 Photos",
                                      ),
                                      background: Colors.redAccent,
                                      position: NotificationPosition.bottom,
                                    );
                                  }
                                },
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kPrimaryColor,
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(12),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        "Add Photo",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: getProportionateScreenWidth(
                                            16,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.add_photo_alternate_outlined,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        GridView.count(
                          crossAxisCount: 2,
                          //  padding: EdgeInsets.all(getProportionateScreenWidth(20)),
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                          physics: ScrollPhysics(),
                          scrollDirection: Axis.vertical,
                          shrinkWrap: true,
                          children: [
                            for (var image in user.images!)
                              GestureDetector(
                                onTap: () {
                                  showCupertinoModalPopup<void>(
                                    context: context,
                                    builder: (BuildContext context) => CupertinoActionSheet(
                                      title: Text("Choose action"),
                                      actions: <CupertinoActionSheetAction>[
                                        CupertinoActionSheetAction(
                                          onPressed: () {
                                            var profilePic = image;
                                            var images = [];
                                            images.add(profilePic);
                                            for (var element in user.images!) {
                                              if (element != profilePic) {
                                                images.add(element);
                                              }
                                            }
                                            DatabaseService.updateUserField(
                                              widget.botId,
                                              {"imagePaths": images},
                                            );
                                            showSimpleNotification(
                                              Text("Profile picture Updated"),
                                              leading: Icon(Icons.done),
                                              position:
                                                  NotificationPosition.bottom,
                                              background: Colors.green,
                                              duration: Duration(seconds: 2),
                                              slideDismissDirection:
                                                  DismissDirection.horizontal,
                                            );
                                            Navigator.pop(context);
                                          },
                                          isDestructiveAction: false,
                                          child: Text("Make Profile Picture"),
                                        ),
                                        CupertinoActionSheetAction(
                                          onPressed: () async {
                                            try {
                                              String storagePath = '';

                                              // Handle different URL formats
                                              if (image.contains('/o/')) {
                                                // Format: https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{encodedPath}?alt=media...
                                                final parts = image.split(
                                                  '/o/',
                                                );
                                                String encodedPath = parts[1];
                                                if (encodedPath.contains('?')) {
                                                  encodedPath = encodedPath
                                                      .split('?')[0];
                                                }
                                                storagePath = Uri.decodeFull(
                                                  encodedPath,
                                                );
                                              } else if (image.startsWith(
                                                'gs://',
                                              )) {
                                                // Format: gs://bucket/path/to/file
                                                storagePath = image
                                                    .replaceFirst(
                                                      RegExp(r'gs://[^/]+/'),
                                                      '',
                                                    );
                                              } else {
                                                // Assume it's already a path string like: profileImages/userId/filename.jpg
                                                storagePath = image;
                                              }

                                              debugPrint(
                                                'Firebase Storage Path: $storagePath',
                                              );

                                              final Reference
                                              firebaseStorageRef =
                                                  FirebaseStorage.instance
                                                      .ref()
                                                      .child(storagePath);

                                              await firebaseStorageRef.delete();

                                              DatabaseService.updateUserField(
                                                widget.botId,
                                                {
                                                  "imagePaths":
                                                      FieldValue.arrayRemove([
                                                        image,
                                                      ]),
                                                },
                                              );
                                              showSimpleNotification(
                                                Text(
                                                  "Photo Deleted Successfully",
                                                ),
                                                leading: Icon(Icons.done),
                                                position:
                                                    NotificationPosition.bottom,
                                                background: Colors.green,
                                                duration: Duration(seconds: 2),
                                                slideDismissDirection:
                                                    DismissDirection.horizontal,
                                              );
                                            } catch (e) {
                                              showSimpleNotification(
                                                Text(
                                                  "Error deleting photo: $e",
                                                ),
                                                leading: Icon(Icons.error),
                                                position:
                                                    NotificationPosition.bottom,
                                                background: Colors.redAccent,
                                                duration: Duration(seconds: 2),
                                                slideDismissDirection:
                                                    DismissDirection.horizontal,
                                              );
                                            }

                                            Navigator.pop(context);
                                          },
                                          isDestructiveAction: true,
                                          child: Text("Delete Picture"),
                                        ),
                                      ],
                                      cancelButton: CupertinoActionSheetAction(
                                        onPressed: () async {
                                          Navigator.pop(context);
                                        },
                                        child: Text("Cancel"),
                                      ),
                                    ),
                                  );
                                },
                                child: PhotoCard(
                                  image: image,
                                  gender: user.gender ?? 'male',
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }
}

class PhotoCard extends StatelessWidget {
  String image;
  String gender;

  PhotoCard({required this.image, required this.gender});

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
            child: ReactiveProfileImage(
              imagePath: image,
              gender: gender,
              width: double.infinity,
              height: double.infinity,
            ),
            // child: CachedNetworkImage(
            //   imageUrl: image,
            //   fit: BoxFit.cover,
            //   alignment: Alignment.topCenter,
            // ),
          ),
          // Align(
          //   alignment: Alignment.topRight,
          //   child: GestureDetector(
          //       onTap: () async {
          //         var fileUrl = Uri.decodeFull(Path.basename(image)).replaceAll(new RegExp(r'(\?alt).*'), '');
          //
          //
          //         final Reference firebaseStorageRef =
          //         FirebaseStorage.instance.ref().child(fileUrl);
          //         await firebaseStorageRef.delete();
          //         DatabaseService.updateField({"images":FieldValue.arrayRemove([image])});
          //
          //         showSimpleNotification(
          //           Text("Photo Deleted Successfully"),
          //           leading: Icon(Icons.done),
          //           position: NotificationPosition.bottom,
          //           background: Colors.redAccent,
          //           duration: Duration(seconds: 2),
          //           slideDismiss: true,
          //         );
          //
          //       },
          //       child: Icon(Icons.delete)),
          // )
        ],
      ),
    );
  }
}
