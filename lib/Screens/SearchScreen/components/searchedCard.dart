import 'package:cached_network_image/cached_network_image.dart';
import 'package:viora/Screens/ProfileScreen/new_profile_view.dart';
import 'package:viora/Screens/ProfileScreen/profileScreen.dart';
import 'package:viora/constants.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';

import '../../../size_config.dart';
import 'package:timeago/timeago.dart' as timeago;

class SearchedCard extends StatefulWidget {
  UserDetails user;

  SearchedCard({required this.user});

  @override
  _SearchedCardState createState() => _SearchedCardState();
}

class _SearchedCardState extends State<SearchedCard> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 3),
      child: GestureDetector(
        onTap: () {
          PersistentNavBarNavigator.pushNewScreen(
            context,
            screen: NewProfileView(uid: widget.user.uid, canPop: true),
            withNavBar: false, // OPTIONAL VALUE. True by default.
            pageTransitionAnimation: PageTransitionAnimation.cupertino,
          );
        },
        child: Card(
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.all(Radius.circular(30)),
                      child: CachedNetworkImage(
                        imageUrl: widget.user.images!.isEmpty
                            ? widget.user.gender == "Male"
                                  ? kMaleUrl
                                  : kFemaleUrl
                            : widget.user.images![0],
                        height: 50,
                        width: 50,
                        fit: BoxFit.cover,
                      ),
                    ),
                    if (widget.user.isOnline!)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 16,
                          width: 16,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.user.name!,
                          style: TextStyle(
                            fontSize: getProportionateScreenWidth(15),
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          " ${widget.user.age}",
                          style: TextStyle(
                            fontSize: getProportionateScreenWidth(15),
                            fontWeight: FontWeight.bold,
                            color: kSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                    Text("${widget.user.city}, ${widget.user.state}"),
                    Text(
                      widget.user.isOnline!
                          ? "Online"
                          : "Active ${timeago.format(DateTime.now().subtract(DateTime.now().difference(widget.user.lastOnline!)))}",
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.all(getProportionateScreenHeight(10)),
                child: SvgPicture.asset(
                  widget.user.gender == "Female"
                      ? "assets/svg/female.svg"
                      : "assets/svg/male.svg",
                  height: getProportionateScreenHeight(24),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
