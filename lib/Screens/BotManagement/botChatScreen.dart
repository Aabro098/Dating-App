import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter/material.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:viora/models/ChatRoom.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:viora/utils/helpers/image_helper.dart';
import '../../constants.dart';
import '../../size_config.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'BotProfile.dart';
import 'botMessageScreen.dart';

class BotChatsScreen extends StatefulHookWidget {
  final String botId;
  BotChatsScreen({required this.botId});

  static String routeName = "/botChatsScreen";

  @override
  _BotChatsScreenState createState() => _BotChatsScreenState();
}

class _BotChatsScreenState extends State<BotChatsScreen> {
  late UserDetails bot;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    getBot();
    DatabaseService.updateUserField(widget.botId, {"unseenCount": 0});
  }

  void getBot() {
    FirebaseFirestore.instance
        .collection("Users")
        .doc(widget.botId)
        .snapshots()
        .listen((event) {
          bot = UserDetails.fromJson(event.data() as Map<String, dynamic>);
          if (mounted) {
            setState(() {
              isLoading = false;
            });
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final refreshKey = useState(DateTime.now());

    if (isLoading) {
      return Scaffold(
        appBar: buildAppBar(),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final query = FirebaseFirestore.instance
        .collection('ChatRooms')
        .orderBy('lastMessageDate', descending: true)
        .where("users", arrayContains: bot.uid);

    return Scaffold(
      appBar: buildAppBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          refreshKey.value = DateTime.now(); // triggers rebuild and refresh
        },
        child: FirestoreQueryBuilder(
          key: ValueKey(refreshKey.value),
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
              return Center(child: Text("Start chatting with someone"));
            }

            return ListView.builder(
              padding: EdgeInsets.all(getProportionateScreenWidth(5)),
              itemCount: snapshot.docs.length,
              itemBuilder: (context, index) {
                if (snapshot.hasMore && index + 1 == snapshot.docs.length) {
                  snapshot.fetchMore();
                }

                final data = snapshot.docs[index].data();
                if (data["lastMessage"] == "") return SizedBox();

                final chatRoom = ChatRoom.fromJson(data);
                return BotChatCard(chatRoom: chatRoom, bot: bot);
              },
            );
          },
        ),
      ),
    );
  }

  AppBar buildAppBar() {
    if (isLoading) {
      return AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: kPrimaryColor,
      );
    }
    return AppBar(
      iconTheme: IconThemeData(color: Colors.white),
      automaticallyImplyLeading: false,
      backgroundColor: kPrimaryColor,
      title: Row(
        children: [
          BackButton(),
          GestureDetector(
            onTap: () {
              PersistentNavBarNavigator.pushNewScreen(
                context,
                screen: BotProfile(botId: bot.uid),
                withNavBar: false,
                pageTransitionAnimation: PageTransitionAnimation.cupertino,
              );
            },
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle),
              clipBehavior: Clip.antiAlias,
              child: ReactiveProfileImage(
                imagePath: bot.images!.isNotEmpty ? bot.images![0] : '',
                gender: bot.gender ?? 'male',
                width: 45,
                height: 45,
              ),
            ),
            // child: ClipRRect(
            //   borderRadius: BorderRadius.all(Radius.circular(30)),
            //   child: CachedNetworkImage(
            //     imageUrl: bot.images!.isEmpty
            //         ? (bot.gender == "Male" ? kMaleUrl : kFemaleUrl)
            //         : bot.images![0],
            //     height: 45,
            //     width: 45,
            //     fit: BoxFit.cover,
            //   ),
            // ),
          ),
          SizedBox(width: kDefaultPadding * 0.75),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${bot.name!} Chat rooms",
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
              Text(
                (bot.isOnline == true ? true : false)
                    ? "Online"
                    : "Active ${timeago.format(DateTime.now().subtract(DateTime.now().difference(bot.lastOnline ?? DateTime.now())))}",
                style: TextStyle(fontSize: 12, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class BotChatCard extends StatefulWidget {
  final ChatRoom chatRoom;
  final UserDetails bot;

  BotChatCard({required this.chatRoom, required this.bot});

  @override
  _BotChatCardState createState() => _BotChatCardState();
}

class _BotChatCardState extends State<BotChatCard> {
  late UserDetails user;
  bool isLoading = true;
  var listener;
  int unSeen = 0;

  @override
  void initState() {
    super.initState();
    getUser();
  }

  @override
  void didUpdateWidget(BotChatCard oldWidget) {
    listener?.cancel();
    getUser();
    super.didUpdateWidget(oldWidget);
  }

  Future<void> getUser() async {
    widget.chatRoom.users.remove(widget.bot.uid);
    CollectionReference usersCol = FirebaseFirestore.instance.collection(
      "Users",
    );

    listener = usersCol.doc(widget.chatRoom.users[0]).snapshots().listen((
      event,
    ) {
      user = UserDetails.fromJson(event.data() as Map<String, dynamic>);
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    });

    FirebaseFirestore.instance
        .collection("Messages")
        .where("roomId", isEqualTo: widget.chatRoom.roomId)
        .where("uid", isEqualTo: widget.chatRoom.users[0])
        .where("seen", isEqualTo: false)
        .snapshots()
        .listen((event) {
          unSeen = event.size;
          if (mounted) {
            setState(() {});
          }
        });
  }

  @override
  void dispose() {
    listener?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return SizedBox();

    return InkWell(
      onTap: () {
        PersistentNavBarNavigator.pushNewScreen(
          context,
          screen: BotMessagesScreen(uId: user.uid, bot: widget.bot),
          withNavBar: false,
          pageTransitionAnimation: PageTransitionAnimation.cupertino,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kDefaultPadding,
          vertical: kDefaultPadding * 0.75,
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  decoration: BoxDecoration(shape: BoxShape.circle),
                  clipBehavior: Clip.antiAlias,
                  child: ReactiveProfileImage(
                    imagePath: user.images?.isNotEmpty == true
                        ? user.images![0]
                        : '',
                    gender: user.gender ?? 'male',
                    width: getProportionateScreenWidth(50),
                    height: getProportionateScreenHeight(50),
                  ),
                  // child: CachedNetworkImage(
                  //   fit: BoxFit.cover,
                  //   alignment: Alignment.topCenter,
                  //   imageUrl: user.images!.isEmpty
                  //       ? (user.gender == "Male" ? kMaleUrl : kFemaleUrl)
                  //       : user.images![0],
                  //   width: 50,
                  //   height: 50,
                  // ),
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
                        border: Border.all(width: 1.5, color: Colors.white),
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
                if (user.isOnline == true)
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
                    DateTime.now().difference(widget.chatRoom.lastMessageDate),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
