import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:viora/Screens/BotManagement/botMessageScreen.dart';
import 'package:viora/Screens/BotManagement/botProfileView.dart';
import 'package:viora/components/customAppBar.dart';
import 'package:viora/constants.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:viora/utils/helpers/image_helper.dart';

import '../../size_config.dart';

class BotUsersView extends HookWidget {
  final UserDetails bot;
  BotUsersView({required this.bot});

  @override
  Widget build(BuildContext context) {
    // Hook state for search text and search results
    final searchController = useTextEditingController();
    final searchResults = useState<List<UserDetails>>([]);
    final isSearching = useState(false);

    void search(String searchkey) async {
      if (searchkey.isEmpty) {
        searchResults.value = [];
        isSearching.value = false;
        return;
      }
      isSearching.value = true;

      final querySnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .orderBy('name')
          .startAt([searchkey])
          .endAt([searchkey + '\uf8ff'])
          .where(
            "gender",
            isEqualTo: bot.gender == "Female" ? "Male" : "Female",
          )
          .get();

      searchResults.value = querySnapshot.docs
          .map((doc) => UserDetails.fromJson(doc.data()))
          .toList();
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),
        child: CustomAppBar(title: "Viewing as ${bot.name}"),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              width: SizeConfig.screenWidth,
              decoration: BoxDecoration(
                color: kSecondaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: TextField(
                controller: searchController,
                keyboardType: TextInputType.name,
                autofocus: false,
                decoration: InputDecoration(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: getProportionateScreenWidth(20),
                    vertical: getProportionateScreenWidth(9),
                  ),
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  hintText: "Search Users",
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (val) {
                  if (val.isEmpty) {
                    searchResults.value = [];
                    isSearching.value = false;
                  } else {
                    search(val);
                  }
                },
              ),
            ),
          ),
          Expanded(
            child: isSearching.value && searchResults.value.isEmpty
                ? Center(child: CircularProgressIndicator())
                : isSearching.value
                ? GridView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.all(8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 20.0,
                      mainAxisSpacing: 20.0,
                    ),
                    itemCount: searchResults.value.length,
                    itemBuilder: (context, index) {
                      return UserCard(
                        user: searchResults.value[index],
                        bot: bot,
                      );
                    },
                  )
                : FirestoreQueryBuilder<Map<String, dynamic>>(
                    // Query users of opposite gender, order by isOnline descending
                    query: FirebaseFirestore.instance
                        .collection('Users')
                        .where(
                          "gender",
                          isEqualTo: bot.gender == "Female" ? "Male" : "Female",
                        )
                        .orderBy("isOnline", descending: true),
                    pageSize: 20,
                    builder: (context, snapshot, _) {
                      if (snapshot.isFetching && snapshot.docs.isEmpty) {
                        return Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      if (snapshot.docs.isEmpty) {
                        return Center(child: Text("No Users found"));
                      }
                      return GridView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.all(
                          getProportionateScreenWidth(20),
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.75,
                          crossAxisSpacing: 20.0,
                          mainAxisSpacing: 20.0,
                        ),
                        itemCount: snapshot.docs.length,
                        itemBuilder: (context, index) {
                          final userData = snapshot.docs[index].data();
                          final user = UserDetails.fromJson(userData);
                          return UserCard(user: user, bot: bot);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class UserCard extends StatelessWidget {
  final UserDetails user;
  final UserDetails bot;

  UserCard({required this.user, required this.bot});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        PersistentNavBarNavigator.pushNewScreen(
          context,
          screen: BotProfileView(uid: user.uid, bot: bot),
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
                imagePath: user.images?.isEmpty ?? true ? '' : user.images![0],
                gender: user.gender ?? 'male',
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
                      (user.isOnline == true ? true : false)
                          ? "Online"
                          : "Offline",
                      style: TextStyle(color: Colors.white),
                    ),
                    Icon(
                      Icons.circle,
                      color: (user.isOnline == true ? true : false)
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
                    "${user.name},${user.age}",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "${user.city},${user.state}",
                    style: TextStyle(color: kSecondaryColor, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 5,
            bottom: 50,
            child: GestureDetector(
              onTap: () {
                PersistentNavBarNavigator.pushNewScreen(
                  context,
                  screen: BotMessagesScreen(uId: user.uid, bot: bot),
                  withNavBar: false,
                  pageTransitionAnimation: PageTransitionAnimation.cupertino,
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SvgPicture.asset("assets/svg/chat.svg", height: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
