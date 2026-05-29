import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:viora/components/verified_badge.dart';
import 'package:viora/utils/constatnts/colors.dart';
import 'package:viora/utils/helpers/image_helper.dart';

import '../../constants.dart';
import '../../size_config.dart';
import 'package:viora/Screens/AdminScreens/AdminProfileView.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:viora/components/customAppBar.dart';

class FemaleUsers extends HookWidget {
  static String routeName = "/femaleUsers";

  @override
  Widget build(BuildContext context) {
    // Optional: Use flutter_hooks useState to force refresh if needed.
    final refreshKey = useState(DateTime.now());

    // Firestore query matching your filtering logic
    final query = FirebaseFirestore.instance
        .collection('Users')
        .where("gender", isEqualTo: "Female")
        .where("fcmToken", isNotEqualTo: "Admin")
        .orderBy('fcmToken')
        .orderBy('joiningDate', descending: true);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),
        child: CustomAppBar(title: "Female Users"),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Trigger paginated query refresh by updating refreshKey
          refreshKey.value = DateTime.now();
        },
        child: FirestoreQueryBuilder(
          key: ValueKey(refreshKey.value), // rebuild widget on refresh

          query: query,
          pageSize: 10,
          builder: (context, snapshot, _) {
            if (snapshot.isFetching) {
              return Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            if (snapshot.docs.isEmpty) {
              return Center(child: Text("No Users found"));
            }

            return GridView.builder(
              padding: EdgeInsets.all(getProportionateScreenWidth(20)),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.75,
                crossAxisSpacing: 20.0,
                mainAxisSpacing: 20.0,
              ),
              itemCount: snapshot.docs.length,
              shrinkWrap: true,
              itemBuilder: (context, index) {
                // Fetch more documents when reaching the last item
                if (snapshot.hasMore && index + 1 == snapshot.docs.length) {
                  snapshot.fetchMore();
                }

                // Extract user data from document snapshot
                final data = snapshot.docs[index].data();
                final user = UserDetails.fromJson(data);

                return UserCard(user: user);
              },
            );
          },
        ),
      ),
    );
  }
}

class UserCard extends StatefulWidget {
  final UserDetails user;

  const UserCard({super.key, required this.user});

  @override
  State<UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<UserCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return GestureDetector(
      onTap: () {
        PersistentNavBarNavigator.pushNewScreen(
          context,
          screen: AdminProfileView(uid: widget.user.uid),
          withNavBar: false,
          pageTransitionAnimation: PageTransitionAnimation.cupertino,
        );
      },
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              child: ReactiveProfileImage(
                imagePath: widget.user.images!.isEmpty
                    ? ''
                    : widget.user.images![0],
                gender: widget.user.gender ?? 'female',
                width: double.infinity,
                height: double.infinity,
              ),
              // child: CachedNetworkImage(
              //   fit: BoxFit.cover,
              //   alignment: Alignment.topCenter,
              //   imageUrl: user.images!.isEmpty
              //       ? (user.gender == "Male" ? kMaleUrl : kFemaleUrl)
              //       : user.images![0],
              //   progressIndicatorBuilder: (context, url, downloadProgress) =>
              //       Center(
              //         child: CircularProgressIndicator(
              //           value: downloadProgress.progress,
              //         ),
              //       ),
              //   errorWidget: (context, url, error) =>
              //       Center(child: Icon(Icons.error)),
              // ),
            ),
          ),
          Align(
            alignment: Alignment.topLeft,
            child: Container(
              margin: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.40),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      (widget.user.isOnline == true ? true : false)
                          ? "Online"
                          : "Offline",
                      style: TextStyle(color: Colors.white),
                    ),
                    Icon(
                      Icons.circle,
                      color: (widget.user.isOnline == true ? true : false)
                          ? Colors.green
                          : Colors.deepOrangeAccent,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              width: double.infinity,
              color: Colors.white.withOpacity(0.90),
              padding: EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "${widget.user.name}, ${widget.user.age}",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "${widget.user.city}, ${widget.user.state}",
                    style: TextStyle(color: kSecondaryColor, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          if (widget.user.isVerified == true)
            Positioned(
              right: 6,
              top: 6,
              child: VerifiedBadge(),
              // child: ReactiveBadgeImage(
              //   badgePath: AppConfigService.verifiedBadgeUri,
              //   width: 22,
              //   height: 22,
              // ),
            ),
        ],
      ),
    );
  }
}
