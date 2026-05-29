import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:viora/Screens/PhotoView/photovioew.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/components/custom_surfix_icon.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';

import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter/cupertino.dart';
import 'package:viora/utils/helpers/image_helper.dart';
import '../../constants.dart';
import '../../size_config.dart';
import 'package:overlay_support/overlay_support.dart';

class AdminProfileView extends StatefulWidget {
  String uid;

  AdminProfileView({required this.uid});

  @override
  _AdminProfileViewState createState() => _AdminProfileViewState();
}

class _AdminProfileViewState extends State<AdminProfileView> {
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    isLoading = true;
    getUser();
  }

  late bool isLoading;
  late UserDetails user;
  final _pageController = PageController();

  Future<void> getUser() async {
    CollectionReference collectionReference = FirebaseFirestore.instance
        .collection("Users");

    await collectionReference.doc(widget.uid).snapshots().listen((value) {
      user = UserDetails.fromJson(value.data() as Map<String, dynamic>);
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    });
    setState(() {});
  }

  _showAddDialog(context) async {
    await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        String title = "Update Coins";
        TextEditingController balCtr = TextEditingController();
        String btnLabel = "Update Now";
        String btnLabelCancel = "Cancel";
        return AlertDialog(
          title: Text(title),
          content: TextFormField(
            controller: balCtr,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: "Amount",
              hintText: "Enter Amount",
              // If  you are using latest version of flutter then lable text and hint text shown like this
              // if you r using flutter less then 1.20.* then maybe this is not working properly
              floatingLabelBehavior: FloatingLabelBehavior.always,
              suffixIcon: CustomSurffixIcon(iconData: Icons.add),
            ),
          ),
          actions: <Widget>[
            ElevatedButton(
              onPressed: () {
                if (balCtr.text.length > 0) {
                  DatabaseService.updateUserField(user.uid, {
                    "coins": FieldValue.increment(int.parse(balCtr.text)),
                  });

                  Navigator.pop(context);
                }
              },
              child: Text(btnLabel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(btnLabelCancel),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    //Image
                    Container(
                      height: getProportionateScreenHeight(450),
                      child: Stack(
                        children: [
                          user.images!.isNotEmpty
                              ? PageView(
                                  physics: BouncingScrollPhysics(),
                                  controller: _pageController,
                                  scrollDirection: Axis.horizontal,
                                  children: List.generate(
                                    user.images?.length ?? 0,
                                    (int index) => GestureDetector(
                                      onTap: () {
                                        PersistentNavBarNavigator.pushNewScreen(
                                          context,
                                          screen: PhotoView(
                                            image: user.images != null
                                                ? user.images![index]
                                                : '',
                                          ),
                                          withNavBar: false,
                                          // OPTIONAL VALUE. True by default.
                                          pageTransitionAnimation:
                                              PageTransitionAnimation.cupertino,
                                        );
                                      },
                                      child: Container(
                                        width: double.infinity,
                                        height: double.infinity,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(10),
                                          ),
                                          child: ReactiveProfileImage(
                                            imagePath: user.images!.isEmpty
                                                ? ''
                                                : user.images![index],
                                            gender: user.gender ?? 'male',
                                            width: double.infinity,
                                            height: double.infinity,
                                          ),
                                          // child: CachedNetworkImage(
                                          //   fit: BoxFit.cover,
                                          //   alignment: Alignment.topCenter,
                                          //   imageUrl: user.images != null
                                          //       ? user.images![index]
                                          //       : '',
                                          //   progressIndicatorBuilder:
                                          //       (
                                          //         context,
                                          //         url,
                                          //         downloadProgress,
                                          //       ) => Center(
                                          //         child:
                                          //             CircularProgressIndicator(
                                          //               value: downloadProgress
                                          //                   .progress,
                                          //             ),
                                          //       ),
                                          //   errorWidget:
                                          //       (context, url, error) => Center(
                                          //         child: Icon(Icons.error),
                                          //       ),
                                          // ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  width: double.infinity,
                                  height: double.infinity,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(10),
                                    ),
                                    child: ReactiveProfileImage(
                                      imagePath: '',
                                      gender: user.gender ?? 'male',
                                      width: double.infinity,
                                      height: double.infinity,
                                    ),
                                    // child: CachedNetworkImage(
                                    //   fit: BoxFit.cover,
                                    //   alignment: Alignment.topCenter,
                                    //   imageUrl: user.images!.isEmpty
                                    //       ? user.gender == "Male"
                                    //             ? "https://mospl.com/wp-content/uploads/2020/07/manager_male_avatar_men_character_professions-512.png"
                                    //             : "https://www.pngitem.com/pimgs/m/22-223925_female-avatar-female-avatar-no-face-hd-png.png"
                                    //       : user.images != null
                                    //       ? user.images![0]
                                    //       : '',
                                    //   progressIndicatorBuilder:
                                    //       (
                                    //         context,
                                    //         url,
                                    //         downloadProgress,
                                    //       ) => Center(
                                    //         child: CircularProgressIndicator(
                                    //           value: downloadProgress.progress,
                                    //         ),
                                    //       ),
                                    //   errorWidget: (context, url, error) =>
                                    //       Center(child: Icon(Icons.error)),
                                    // ),
                                  ),
                                ),

                          //online Indicator
                          Align(
                            alignment: Alignment.bottomRight,
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
                                            "Active " +
                                                timeago.format(
                                                  DateTime.now().subtract(
                                                    DateTime.now().difference(
                                                      user.lastOnline ??
                                                          DateTime.now(),
                                                    ),
                                                  ),
                                                ),
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                    Icon(
                                      Icons.circle,
                                      color:
                                          (user.isOnline == true ? true : false)
                                          ? Colors.green
                                          : Colors.deepOrangeAccent,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          user.images!.length > 1
                              ? Align(
                                  alignment: Alignment.bottomLeft,
                                  child: Padding(
                                    padding: EdgeInsets.all(8.8),
                                    child: SmoothPageIndicator(
                                      controller: _pageController,
                                      count: user.images != null
                                          ? user.images!.length
                                          : 0,
                                      effect: ExpandingDotsEffect(
                                        activeDotColor: Colors.white,
                                        dotColor: Colors.white.withOpacity(0.5),
                                        dotHeight: 8.8,
                                        dotWidth: 12,
                                        spacing: 4.8,
                                      ),
                                    ),
                                  ),
                                )
                              : SizedBox(),

                          //Report User
                          SafeArea(
                            child: Align(
                              alignment: Alignment.topRight,
                              child: GestureDetector(
                                onTap: () {
                                  showCupertinoModalPopup<void>(
                                    context: context,
                                    builder: (BuildContext context) =>
                                        CupertinoActionSheet(
                                          title: Text(
                                            user.isDisabled == true
                                                ? "Enable User"
                                                : "Disable User",
                                          ),
                                          message: Text("Can changed anytime"),
                                          actions: <CupertinoActionSheetAction>[
                                            CupertinoActionSheetAction(
                                              onPressed: () async {
                                                DatabaseService.updateUserField(
                                                  widget.uid,
                                                  {
                                                    "isDisabled":
                                                        !(user.isDisabled ==
                                                                true
                                                            ? true
                                                            : false),
                                                  },
                                                );

                                                Navigator.pop(context);
                                                showSimpleNotification(
                                                  Text("Action Completed"),
                                                  background:
                                                      !(user.isDisabled == true
                                                          ? true
                                                          : false)
                                                      ? Colors.redAccent
                                                      : Colors.green,
                                                  duration: Duration(
                                                    seconds: 3,
                                                  ),
                                                  position: NotificationPosition
                                                      .bottom,
                                                  slideDismiss: true,
                                                  leading: Icon(
                                                    !(user.isDisabled == true
                                                            ? true
                                                            : false)
                                                        ? Icons.close
                                                        : Icons.verified,
                                                  ),
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
                                  margin: EdgeInsets.symmetric(
                                    vertical: 25,
                                    horizontal: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (user.isDisabled == true ? true : false)
                                        ? Colors.green.withOpacity(0.80)
                                        : Colors.redAccent.withOpacity(0.80),
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
                                        Icon(
                                          Icons.report,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        Text(
                                          (user.isDisabled == true
                                                  ? true
                                                  : false)
                                              ? "Enable User"
                                              : "Disable User",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          //BackButton
                          SafeArea(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Padding(
                                padding: const EdgeInsets.all(25),
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context);
                                  },
                                  child: Icon(Icons.arrow_back_ios),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    //Details
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SvgPicture.asset(
                                "assets/svg/coins.svg",
                                color: Colors.orangeAccent,
                                width: getProportionateScreenWidth(20),
                              ),
                              SizedBox(width: 4),
                              Text(
                                user.coins.toString(),
                                style: TextStyle(
                                  fontSize: getProportionateScreenWidth(22),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Spacer(),
                              InkWell(
                                onTap: () {
                                  _showAddDialog(context);
                                },
                                child: Icon(Icons.add_circle),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Icon(
                                Icons.person_pin,
                                size: getProportionateScreenWidth(26),
                              ),
                              Text(
                                user.name ?? 'name',
                                style: TextStyle(
                                  fontSize: getProportionateScreenWidth(22),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "  ${user.age}",
                                style: TextStyle(
                                  fontSize: getProportionateScreenWidth(22),
                                  fontWeight: FontWeight.bold,
                                  color: kSecondaryColor,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: getProportionateScreenWidth(26),
                              ),
                              Text(
                                user.city ?? "city",
                                style: TextStyle(
                                  fontSize: getProportionateScreenWidth(18),
                                  color: kSecondaryColor,
                                ),
                              ),
                              Text(
                                ", ${user.state}",
                                style: TextStyle(
                                  fontSize: getProportionateScreenWidth(18),
                                  color: kSecondaryColor,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text("UID : "),
                              SelectableText(
                                user.uid,
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              GestureDetector(
                                onTap: () {
                                  DatabaseService.getMessageCount(user.uid);
                                },
                                child: Icon(Icons.message),
                              ),
                            ],
                          ),
                          SizedBox(height: getProportionateScreenHeight(20)),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Sexual Orientation"),
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
                              Text("Marital Status"),
                              Wrap(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    child: Chip(
                                      label: Text(
                                        user.maritalStatus ?? "maritialStatus",
                                      ),
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
                                  ? Text("Types of Relationship looking for")
                                  : SizedBox(),
                              Wrap(
                                direction: Axis.horizontal,
                                children: [
                                  for (var i in user.relTypes ?? [])
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
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
