import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:viora/Screens/MessagesScreen/new_message_screen.dart';
import 'package:viora/Screens/ProfileScreen/new_profile_view.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:viora/utils/helpers/image_helper.dart';

import '../../../constants.dart';
import 'package:viora/models/ChatRoom.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../size_config.dart';
import '../../../Services/exceptions/exceptions.dart';

class ChatCard extends StatefulWidget {
  ChatCard({required this.chatRoom});

  ChatRoom chatRoom;

  @override
  _ChatCardState createState() => _ChatCardState();
}

class _ChatCardState extends State<ChatCard> {
  // Helper for conditional logging
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[ChatCard] $message');
    }
  }

  @override
  void initState() {
    super.initState();
    isLoading = true;
    getUser();
  }

  @override
  void didUpdateWidget(ChatCard oldWidget) {
    listner?.cancel();

    getUser();

    super.didUpdateWidget(oldWidget);
  }

  late UserDetails user;
  late bool isLoading;
  var listner;
  int unSeen = 0;

  Future<void> getUser() async {
    widget.chatRoom.users.remove(FirebaseAuth.instance.currentUser!.uid);
    CollectionReference collectionReference = FirebaseFirestore.instance
        .collection("Users");

    listner = collectionReference
        .doc(widget.chatRoom.users[0])
        .snapshots()
        .listen(
          (event) {
            user = UserDetails.fromJson(event.data() as Map<String, dynamic>);

            if (mounted) {
              setState(() {
                isLoading = false;
              });
            }
          },
          onError: (error, stackTrace) {
            _log('Error fetching user: $error');
            final appException = ErrorHandler.convert(error, stackTrace);
            _log('Converted to: ${appException.runtimeType}');
            if (mounted) {
              setState(() {
                isLoading = false;
              });
            }
          },
        );

    FirebaseFirestore.instance
        .collection("Messages")
        .where("roomId", isEqualTo: widget.chatRoom.roomId)
        .where("uid", isEqualTo: widget.chatRoom.users[0])
        .where("seen", isEqualTo: false)
        .snapshots()
        .listen(
          (event) {
            unSeen = event.size;
            if (mounted) {
              setState(() {});
            }
          },
          onError: (error, stackTrace) {
            _log('Error fetching unseen messages: $error');
            // Silent error - don't show to user, just log
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    return isLoading
        ? SizedBox()
        : user.isDisabled!
        ? buildDisabledUser()
        : InkWell(
            onTap: () {
              PersistentNavBarNavigator.pushNewScreen(
                context,
                screen: NewMessagesScreen(uId: user.uid),
                withNavBar: false, // OPTIONAL VALUE. True by default.
                pageTransitionAnimation: PageTransitionAnimation.cupertino,
              );
            },
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: kDefaultPadding * 0.5,
                vertical: kDefaultPadding * 0.75,
              ),
              child: Row(
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                        child: CachedNetworkImage(
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          imageUrl: user.images!.isEmpty
                              ? user.gender == "Male"
                                    ? kMaleUrl
                                    : kFemaleUrl
                              : user.images![0],
                          width: 50,
                          height: 50,
                        ),
                      ),
                      if (unSeen > 0)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            height: getProportionateScreenWidth(16),
                            width: getProportionateScreenWidth(16),
                            decoration: BoxDecoration(
                              color: Colors.deepOrange[400],
                              shape: BoxShape.circle,
                              border: Border.all(
                                width: 1.5,
                                color: Colors.white,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                unSeen < 9 ? unSeen.toString() : "9+",
                                style: TextStyle(
                                  fontSize: getProportionateScreenWidth(10),
                                  height: 1,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (user.isOnline!)
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
                                color: Theme.of(
                                  context,
                                ).scaffoldBackgroundColor,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kDefaultPadding,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name!,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: unSeen > 0
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                          user.isTyping == widget.chatRoom.roomId
                              ? Text(
                                  "Typing...",
                                  style: TextStyle(
                                    color: Colors.orangeAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : Opacity(
                                  opacity: unSeen > 0 ? 1 : 0.64,
                                  child: Text(
                                    widget.chatRoom.lastMessage.contains(
                                          "vioraa.firebasestorage.app",
                                        )
                                        ? "Image"
                                        : widget.chatRoom.lastMessage,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: unSeen > 0
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: 0.64,
                    child: Text(
                      timeago.format(
                        DateTime.now().subtract(
                          DateTime.now().difference(
                            widget.chatRoom.lastMessageDate,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
  }

  buildDisabledUser() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(
        horizontal: kDefaultPadding * 0.5,
        vertical: kDefaultPadding * 0.75,
      ),
      child: Row(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(24)),
                child: CachedNetworkImage(
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  imageUrl: user.gender == "Male" ? kMaleUrl : kFemaleUrl,
                  width: 50,
                  height: 50,
                ),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: kDefaultPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Viora User",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  Opacity(
                    opacity: 0.64,
                    child: Text(
                      "User left or Disabled",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.normal),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// // ignore: must_be_immutable
// class ChatCard extends StatefulWidget {
//   ChatCard({this.chatRoom});
//
//   ChatRoom chatRoom;
//
//   @override
//   _ChatCardState createState() => _ChatCardState();
// }
//
// class _ChatCardState extends State<ChatCard> {
//   @override
//   void initState() {
//     // TODO: implement initState
//     super.initState();
//     isLoading = true;
//     getUser();
//   }
//
//   @override
//   void didUpdateWidget(ChatCard oldWidget) {
//     getUser();
//
//     super.didUpdateWidget(oldWidget);
//   }
//
//   UserDetails user = new UserDetails();
//   bool isLoading;
//
//   Future<void> getUser() async {
//     widget.chatRoom.users.remove(FirebaseAuth.instance.currentUser.uid);
//     CollectionReference collectionReference =
//         FirebaseFirestore.instance.collection("Users");
//
//     collectionReference.doc(widget.chatRoom.users[0]).get().then((event) {
//       user = null;
//       user = UserDetails.fromJson(event.data());
//
//       setState(() {
//         isLoading = false;
//       });
//     });
//
//     setState(() {});
//
//
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return isLoading
//         ? SizedBox()
//         : InkWell(
//             onTap: () {
//               PersistentNavBarNavigator.pushNewScreen(
//                 context,
//                 screen: MessagesScreen(
//                   uId: user.uid,
//                 ),
//                 withNavBar: false, // OPTIONAL VALUE. True by default.
//                 pageTransitionAnimation: PageTransitionAnimation.cupertino,
//               );
//             },
//             child: Padding(
//               padding: const EdgeInsets.symmetric(
//                   horizontal: kDefaultPadding,
//                   vertical: kDefaultPadding * 0.75),
//               child: Row(
//                 children: [
//                   Stack(
//                     children: [
//                       ClipRRect(
//                           borderRadius: BorderRadius.all(Radius.circular(24)),
//                           child: CachedNetworkImage(
//                             imageUrl: user.images.isEmpty
//                                 ? user.gender == "Male"
//                                     ? kMaleUrl
//                                     : kFemaleUrl
//                                 : user.images[0],
//                             width: 50,
//                             height: 50,
//                           )),
//                       if (user.isOnline)
//                         Positioned(
//                           right: 0,
//                           bottom: 0,
//                           child: Container(
//                             height: 16,
//                             width: 16,
//                             decoration: BoxDecoration(
//                               color: Colors.green,
//                               shape: BoxShape.circle,
//                               border: Border.all(
//                                   color:
//                                       Theme.of(context).scaffoldBackgroundColor,
//                                   width: 3),
//                             ),
//                           ),
//                         )
//                     ],
//                   ),
//                   Expanded(
//                     child: Padding(
//                       padding: const EdgeInsets.symmetric(
//                           horizontal: kDefaultPadding),
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             user.name,
//                             style: TextStyle(
//                                 fontSize: 16, fontWeight: FontWeight.w500),
//                           ),
//                           Opacity(
//                             opacity: 0.64,
//                             child: Text(
//                               widget.chatRoom.lastMessage,
//                               maxLines: 1,
//                               overflow: TextOverflow.ellipsis,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                   Opacity(
//                     opacity: 0.64,
//                     child: Text(timeago.format(DateTime.now().subtract(
//                         DateTime.now()
//                             .difference(widget.chatRoom.lastMessageDate)))),
//                   ),
//                 ],
//               ),
//             ),
//           );
//   }
// }
/// New Interaction style ChatCard matching the design
class InteractionChatCard extends StatefulWidget {
  final ChatRoom chatRoom;
  final bool isFirst;
  final bool isLast;

  const InteractionChatCard({
    required this.chatRoom,
    this.isFirst = false,
    this.isLast = false,
    super.key,
  });

  @override
  InteractionChatCardState createState() => InteractionChatCardState();
}

class InteractionChatCardState extends State<InteractionChatCard> {
  UserDetails? user;
  late bool isLoading;
  var listner;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _unseenListener;
  int unSeen = 0;
  bool isSentByMe = false;
  bool isTapped = false; // Track tap state for purple highlight

  // Helper for conditional logging
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[InteractionChatCard] $message');
    }
  }

  @override
  void initState() {
    super.initState();
    isLoading = true;
    getUser();
  }

  @override
  void didUpdateWidget(InteractionChatCard oldWidget) {
    listner?.cancel();
    _unseenListener?.cancel();
    getUser();
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    listner?.cancel();
    _unseenListener?.cancel();
    super.dispose();
  }

  Future<void> getUser() async {
    final currentAuthUser = FirebaseAuth.instance.currentUser;
    if (currentAuthUser == null) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
      return;
    }

    final currentUserId = currentAuthUser.uid;
    final otherUserId = widget.chatRoom.users.firstWhere(
      (id) => id != currentUserId,
      orElse: () => widget.chatRoom.users[0],
    );

    CollectionReference collectionReference = FirebaseFirestore.instance
        .collection("Users");

    listner = collectionReference
        .doc(otherUserId)
        .snapshots()
        .listen(
          (event) {
            if (!event.exists || event.data() == null) {
              if (mounted) {
                setState(() {
                  isLoading = false;
                });
              }
              return;
            }

            user = UserDetails.fromJson(event.data() as Map<String, dynamic>);

            if (mounted) {
              setState(() {
                isLoading = false;
              });
            }
          },
          onError: (error, stackTrace) {
            _log('Error fetching user: $error');
            final appException = ErrorHandler.convert(error, stackTrace);
            _log('Converted to: ${appException.runtimeType}');
            if (mounted) {
              setState(() {
                isLoading = false;
              });
            }
          },
        );

    // Get unseen messages count
    _unseenListener?.cancel();
    _unseenListener = FirebaseFirestore.instance
        .collection("Messages")
        .where("roomId", isEqualTo: widget.chatRoom.roomId)
        .where("uid", isEqualTo: otherUserId)
        .where("seen", isEqualTo: false)
        .snapshots()
        .listen(
          (event) {
            unSeen = event.size;
            if (mounted) {
              setState(() {});
            }
          },
          onError: (error, stackTrace) {
            _log('Error fetching unseen messages: $error');
            // During logout/signout, Firestore can return permission-denied while
            // old listeners are still active; stop this listener to avoid log spam.
            if (error.toString().contains('permission-denied')) {
              _unseenListener?.cancel();
              _unseenListener = null;
            }
          },
        );

    // Check if last message was sent by current user
    isSentByMe =
        widget.chatRoom.lastMessage.startsWith('You:') ||
        widget.chatRoom.users.indexOf(currentUserId) == 0;
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    final difference = today.difference(messageDate).inDays;

    if (difference == 0) {
      // Today - show time
      final hour = dateTime.hour;
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'pm' : 'am';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:$minute $period';
    } else if (difference == 1) {
      return 'Yesterday';
    } else if (difference < 7) {
      return '$difference days ago';
    } else {
      final weeks = (difference / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't display anything if user data is null or doesn't exist
    if (user == null && !isLoading) {
      return const SizedBox.shrink();
    }

    // Show nothing while loading
    if (isLoading) {
      return const SizedBox.shrink();
    }

    if (user!.isDisabled == true) {
      return Container(
        margin: widget.isLast
            ? null
            : EdgeInsets.only(bottom: getProportionateScreenHeight(8)),
        child: _buildDisabledCard(),
      );
    }

    final bool hasUnread = unSeen > 0;

    return Container(
      margin: widget.isLast
          ? null
          : EdgeInsets.only(bottom: getProportionateScreenHeight(8)),
      child: GestureDetector(
        onTap: () async {
          if (isTapped) return;
          // Show purple background briefly
          if (mounted) {
            setState(() {
              isTapped = true;
            });
          }
          // Navigate to messages screen
          PersistentNavBarNavigator.pushNewScreen(
            context,
            // Changed to NewMessagesScreen to leverage new chat room initialization logic before it was MessageScreen
            screen: NewMessagesScreen(uId: user!.uid),
            withNavBar: false,
            pageTransitionAnimation: PageTransitionAnimation.cupertino,
          );

          // Reset tap state after navigation
          if (mounted) {
            setState(() {
              isTapped = false;
            });
          }
        },
        child: Container(
          width: double.infinity,
          height: getProportionateScreenHeight(87),
          decoration: BoxDecoration(
            color: isTapped
                ? const Color(0xFFF2DBFF) // Purple when tapped
                : Colors.white, // White otherwise
            borderRadius: BorderRadius.circular(
              getProportionateScreenWidth(14),
            ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: getProportionateScreenWidth(12),
            vertical: getProportionateScreenHeight(12),
          ),
          child: Row(
            children: [
              // Avatar with unread badge
              Stack(
                children: [
                  Container(
                    // width: getProportionateScreenWidth(63),
                    // height: getProportionateScreenWidth(63),
                    // decoration: BoxDecoration(
                    //   shape: BoxShape.circle,
                    //   border: Border.all(
                    //     color: Colors.white.withOpacity(0.8),
                    //     width: 1,
                    //   ),
                    // ),
                    child: Container(
                      width: getProportionateScreenWidth(58),
                      height: getProportionateScreenWidth(58),
                      decoration: BoxDecoration(shape: BoxShape.circle),
                      // borderRadius: BorderRadius.circular(
                      //   getProportionateScreenWidth(31.5),
                      // ),
                      clipBehavior: Clip.antiAlias,
                      child: ReactiveProfileImage(
                        imagePath: user?.images?.isNotEmpty == true
                            ? user!.images![0]
                            : '',
                        gender: user?.gender ?? "male",
                        width: getProportionateScreenWidth(58),
                        height: getProportionateScreenWidth(58),
                      ),
                      // child: CachedNetworkImage(
                      //   fit: BoxFit.cover,
                      //   alignment: Alignment.topCenter,
                      //   imageUrl: user?.images?.isNotEmpty == true
                      //       ? user!.images![0]
                      //       : (user?.gender == "Male" ? kMaleUrl : kFemaleUrl),
                      //   width: getProportionateScreenWidth(63),
                      //   height: getProportionateScreenWidth(63),
                      //   placeholder: (context, url) =>
                      //       Container(color: Colors.grey[200]),
                      //   errorWidget: (context, url, error) => Container(
                      //     color: Colors.grey[200],
                      //     child: const Icon(Icons.person, color: Colors.grey),
                      //   ),
                      // ),
                    ),
                  ),
                  // Unread message badge
                  if (hasUnread)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        height: getProportionateScreenWidth(20),
                        width: getProportionateScreenWidth(20),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange[400],
                          shape: BoxShape.circle,
                          border: Border.all(width: 2, color: Colors.white),
                        ),
                        child: Center(
                          child: Text(
                            unSeen < 9 ? unSeen.toString() : "9+",
                            style: TextStyle(
                              fontSize: getProportionateScreenWidth(10),
                              height: 1,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Online indicator
                  if (user?.isOnline == true && !hasUnread)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        height: getProportionateScreenWidth(14),
                        width: getProportionateScreenWidth(14),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),

              SizedBox(width: getProportionateScreenWidth(11)),

              // Name and Message
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name ?? 'Unknown',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: getProportionateScreenWidth(18),
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: getProportionateScreenHeight(2)),
                    user?.isTyping == widget.chatRoom.roomId
                        ? Text(
                            "Typing...",
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: getProportionateScreenWidth(16),
                              fontWeight: FontWeight.w600,
                              color: Colors.orangeAccent,
                            ),
                          )
                        : Text(
                            _getMessagePreview(),
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: getProportionateScreenWidth(16),
                              fontWeight: hasUnread
                                  ? FontWeight
                                        .w700 // Bold for unread
                                  : FontWeight.w500, // Normal for read
                              color: hasUnread
                                  ? Colors
                                        .black // Black for unread
                                  : const Color(0xFF8E8E8E), // Gray for read
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ],
                ),
              ),

              SizedBox(width: getProportionateScreenWidth(8)),

              // Time - positioned at the top
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    _formatTime(widget.chatRoom.lastMessageDate),
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: getProportionateScreenWidth(14),
                      fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                      color: hasUnread ? Colors.black : const Color(0xFF797979),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getMessagePreview() {
    String message = widget.chatRoom.lastMessage;

    if (message.contains("vioraa.firebasestorage.app")) {
      message = "Image";
    }

    if (isSentByMe) {
      return "You: $message";
    }

    return message;
  }

  Widget _buildDisabledCard() {
    return Container(
      width: double.infinity,
      height: getProportionateScreenHeight(87),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.75),
        borderRadius: BorderRadius.circular(getProportionateScreenWidth(14)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: getProportionateScreenWidth(12),
        vertical: getProportionateScreenHeight(12),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: getProportionateScreenWidth(63),
            height: getProportionateScreenWidth(63),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.8),
                width: 1,
              ),
              color: Colors.grey[200],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                getProportionateScreenWidth(31.5),
              ),
              child: CachedNetworkImage(
                fit: BoxFit.cover,
                imageUrl: user?.gender == "Male" ? kMaleUrl : kFemaleUrl,
                width: getProportionateScreenWidth(63),
                height: getProportionateScreenWidth(63),
              ),
            ),
          ),

          SizedBox(width: getProportionateScreenWidth(11)),

          // Name and Message
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Viora User',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: getProportionateScreenWidth(18),
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: getProportionateScreenHeight(2)),
                Text(
                  'User left or Disabled',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: getProportionateScreenWidth(16),
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF8E8E8E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
