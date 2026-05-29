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

class MaleUsers extends HookWidget {
  static String routeName = "/maleUsers";

  @override
  Widget build(BuildContext context) {
    // Hooks state to force refresh on pull to refresh
    final refreshKey = useState(DateTime.now());

    final query = FirebaseFirestore.instance
        .collection('Users')
        .where("gender", isEqualTo: "Male")
        .orderBy('joiningDate', descending: true);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),
        child: CustomAppBar(title: "Male Users"),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Update key to rebuild FirestoreQueryBuilder and refresh data
          refreshKey.value = DateTime.now();
        },
        child: FirestoreQueryBuilder(
          key: ValueKey(refreshKey.value), // rebuild to refresh data
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
                // Auto fetch next page when near end
                if (snapshot.hasMore && index + 1 == snapshot.docs.length) {
                  snapshot.fetchMore();
                }

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

// UserCard remains unchanged
class UserCard extends StatefulWidget {
  final UserDetails user;

  UserCard({required this.user});

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
                gender: widget.user.gender ?? 'male',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "${widget.user.name},${widget.user.age}",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "${widget.user.city},${widget.user.state}",
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
