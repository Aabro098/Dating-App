import 'package:flutter/material.dart';
import 'package:viora/size_config.dart';
import 'package:viora/components/customAppBar.dart';
import 'package:viora/constants.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:viora/Screens/AdminScreens/MaleUsers.dart';

class SearchUser extends StatefulWidget {
  static String routeName = "/searchScreen";
  @override
  _SearchUserState createState() => _SearchUserState();
}

class _SearchUserState extends State<SearchUser> {
  final TextEditingController tc = new TextEditingController();
  List<UserDetails> users = [];

  search(searchkey) {
    FirebaseFirestore.instance
        .collection('Users')
        .orderBy('name')
        .startAt([searchkey])
        .endAt([searchkey + '\uf8ff'])
        .get()
        .then((snapshot) {
          users.clear();
          snapshot.docs.forEach((element) {
            users.add(UserDetails.fromJson(element.data()));
          });
          setState(() {});
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),

        child: CustomAppBar(title: "Search"),
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
                keyboardType: TextInputType.name,
                autofocus: false,
                controller: tc,
                onChanged: (val) {
                  search(val);
                },
                onSubmitted: (value) {},
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
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 1,

                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
              ),
              itemCount: users.length,
              itemBuilder: (BuildContext ctx, index) {
                return UserCard(user: users[index]);
              },
            ),
          ),
        ],
      ),
    );
  }
}
