import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:viora/Screens/BotManagement/botProfileView.dart';
import 'package:viora/Screens/MessagesScreen/components/text_message.dart';
import 'package:viora/Services/AppConfigService.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/Services/ImageUploadService.dart';
import 'package:viora/Services/MessageAndChatRepository.dart';
import 'package:viora/models/ReportedUser.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:viora/models/ChatRoom.dart';
import 'package:viora/utils/helpers/image_helper.dart';
import '../../constants.dart';
import '../../size_config.dart';
import 'package:viora/models/Message.dart';
import 'package:viora/Services/ChatService.dart';

class BotMessagesScreen extends StatefulHookWidget {
  final String uId;
  final UserDetails bot;

  BotMessagesScreen({required this.uId, required this.bot});

  @override
  _BotMessagesScreenState createState() => _BotMessagesScreenState();
}

class _BotMessagesScreenState extends State<BotMessagesScreen> {
  late bool isLoading;
  late UserDetails user;
  late ChatRoom chatRoom;
  late bool isTyping;
  final messageCtr = TextEditingController();
  bool show = false;

  @override
  void initState() {
    super.initState();
    isLoading = true;
    getUser();
  }

  @override
  void dispose() {
    DatabaseService.updateUserField(widget.bot.uid, {"isTyping": ""});
    super.dispose();
  }

  Future<void> getUser() async {
    FirebaseFirestore.instance
        .collection("Users")
        .doc(widget.uId)
        .snapshots()
        .listen((event) {
          user = UserDetails.fromJson(event.data() as Map<String, dynamic>);
          if (mounted) setState(() {});
        });

    await checkRoom();
  }

  String checkUserID(String user1, String user2) {
    if (user1.compareTo(user2) == 1) {
      return user2 + "_" + user1;
    } else if (user2.compareTo(user1) == 1) {
      return user1 + "_" + user2;
    }
    return '';
  }

  Future<void> checkRoom() async {
    var user2 = widget.bot.uid;
    var user1 = widget.uId;

    var path = user1.codeUnitAt(0) == user2.codeUnitAt(0)
        ? checkUserID(user1, user2)
        : user1.codeUnitAt(0) < user2.codeUnitAt(0)
        ? user1 + "_" + user2
        : user2 + "_" + user1;

    var doc = await FirebaseFirestore.instance
        .collection("ChatRooms")
        .doc(path)
        .get();

    if (doc.exists) {
      chatRoom = ChatRoom.fromJson(doc.data() as Map<String, dynamic>);
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    } else {
      ChatRoom newChatRoom = ChatRoom(
        lastMessage: "",
        lastMessageDate: DateTime.now(),
        blockedBy: '',
        isBlocked: false,
        users: [widget.uId, widget.bot.uid],
      );
      await ChatService.addBotChatRoom(newChatRoom, context);
      await checkRoom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final refreshKey = useState(DateTime.now());

    return Scaffold(
      appBar: buildAppBar(),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.orangeAccent,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text("Chatting as ${widget.bot.name}"),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kDefaultPadding,
                    ),
                    child: GestureDetector(
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: RefreshIndicator(
                        onRefresh: () async {
                          refreshKey.value = DateTime.now(); // refresh messages
                        },
                        child: FirestoreQueryBuilder(
                          key: ValueKey(refreshKey.value),
                          query: FirebaseFirestore.instance
                              .collection('Messages')
                              .where("roomId", isEqualTo: chatRoom.roomId)
                              .orderBy('date', descending: true),
                          pageSize: 5,
                          builder: (context, snapshot, _) {
                            if (snapshot.hasError) {
                              return Center(
                                child: Text('Error: ${snapshot.error}'),
                              );
                            }
                            if (snapshot.isFetching && snapshot.docs.isEmpty) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (snapshot.docs.isEmpty) {
                              return Center(
                                child: Text("Say Hi to start Conversation"),
                              );
                            }
                            return ListView.builder(
                              reverse: true,
                              padding: EdgeInsets.all(
                                getProportionateScreenWidth(5),
                              ),
                              itemCount: snapshot.docs.length,
                              itemBuilder: (context, index) {
                                if (snapshot.hasMore &&
                                    index + 1 == snapshot.docs.length) {
                                  snapshot.fetchMore();
                                }
                                final data = snapshot.docs[index].data();
                                final message = MessageModel.fromJson(data);
                                return BotMessage(
                                  docId: snapshot.docs[index].id,
                                  message: message,
                                  picUrl: user.images!.isEmpty
                                      ? user.gender == "Male"
                                            ? AppConfigService.maleImageUrl
                                            : AppConfigService.femaleImageUrl
                                      : user.images![0],
                                  botId: widget.bot.uid,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                chatRoom.isBlocked
                    ? _buildBlockedState(context, chatRoom)
                    : buildMessageInput(),
              ],
            ),
    );
  }

  /// Shows blocked chat room state
  Widget _buildBlockedState(BuildContext context, ChatRoom chatRoom) {
    return SafeArea(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Spacer(),
          const Icon(Icons.block, color: Colors.redAccent),
          const Text(
            "Chat Room Blocked",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (chatRoom.blockedBy == widget.bot.uid)
            ElevatedButton(
              onPressed: () async {
                await ChatRoomRepository.unblockChatRoom(
                  chatRoom.roomId,
                  widget.bot.uid,
                );
                getUser();
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(kPrimaryColor),
                foregroundColor: WidgetStateProperty.all(Colors.white),
                padding: WidgetStateProperty.all(const EdgeInsets.all(8.0)),
              ),
              child: const Text("Unblock"),
            ),
        ],
      ),
    );
  }

  Widget buildMessageInput() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: kDefaultPadding,
        vertical: kDefaultPadding / 2,
      ),
      decoration: BoxDecoration(
        color: Colors.transparent,
        boxShadow: [
          BoxShadow(
            offset: Offset(0, 4),
            blurRadius: 32,
            color: Color(0xFF087949).withOpacity(0.08),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            GestureDetector(
              onTap: () {
                MessageModel message = MessageModel(
                  seen: false,
                  date: DateTime.now(),
                  uid: widget.bot.uid,
                  receiver: user.uid,
                  text: "Image",
                  roomId: chatRoom.roomId,
                );

                ImageUploadService.sendBotImageMessage(
                  context,
                  message,
                  widget.bot,
                  user.fcmToken,
                  chatRoom.roomId,
                );
              },
              child: Container(
                padding: EdgeInsets.all(getProportionateScreenWidth(12)),
                height: getProportionateScreenWidth(46),
                width: getProportionateScreenWidth(46),
                decoration: BoxDecoration(
                  color: kPrimaryColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.image, color: Colors.white),
              ),
            ),
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: kDefaultPadding * 0.75,
                ),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Row(
                  children: [
                    SizedBox(width: kDefaultPadding / 4),
                    Expanded(
                      child: TextField(
                        controller: messageCtr,
                        onChanged: (text) {
                          if (text.isEmpty) {
                            DatabaseService.updateUserField(widget.bot.uid, {
                              "isTyping": "",
                            });
                          }
                          isTyping = text.trim().isNotEmpty;
                          if (isTyping) {
                            setState(() => show = true);
                            DatabaseService.updateUserField(widget.bot.uid, {
                              "isTyping": chatRoom.roomId,
                            });
                          } else {
                            setState(() => show = false);
                          }
                        },
                        keyboardType: TextInputType.multiline,
                        minLines: 1,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText: "Type message",
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    SizedBox(width: kDefaultPadding / 4),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                DatabaseService.updateUserField(widget.bot.uid, {
                  "isTyping": "",
                });
                String messageText = messageCtr.text.trim();
                messageCtr.clear();
                if (messageText.isNotEmpty) {
                  MessageModel message = MessageModel(
                    seen: false,
                    date: DateTime.now(),
                    uid: widget.bot.uid,
                    receiver: user.uid,
                    text: messageText,
                    roomId: chatRoom.roomId,
                  );
                  ChatService.sendBotMessage(message);
                  setState(() {});
                  // FCM is sent by functions/notifications/onMessageCreated.js when the
                  // Messages doc is created. Do not call NotificationService.sendNotification
                  // here — it duplicates that push for the receiver.
                }
              },
              child: Container(
                padding: EdgeInsets.all(getProportionateScreenWidth(12)),
                height: getProportionateScreenWidth(46),
                width: getProportionateScreenWidth(46),
                decoration: BoxDecoration(
                  color: kPrimaryColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.send, color: Colors.white),
              ),
            ),
          ],
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
                screen: BotProfileView(uid: user.uid, bot: widget.bot),
                withNavBar: false,
                pageTransitionAnimation: PageTransitionAnimation.cupertino,
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(30)),
              child: ReactiveProfileImage(
                imagePath: user.images?.isNotEmpty == true
                    ? user.images![0]
                    : '',
                height: 45,
                width: 45,
                gender: user.gender ?? 'male',
              ),
              // child: CachedNetworkImage(
              //   imageUrl: user.images!.isEmpty
              //       ? (user.gender == "Male" ? kMaleUrl : kFemaleUrl)
              //       : user.images![0],
              //   height: 45,
              //   width: 45,
              //   fit: BoxFit.cover,
              // ),
            ),
          ),
          SizedBox(width: kDefaultPadding * 0.75),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.name!,
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
              Text(
                user.isTyping == chatRoom.roomId
                    ? "Typing..."
                    : user.isOnline!
                    ? "Online"
                    : "Active ${timeago.format(DateTime.now().subtract(DateTime.now().difference(user.lastOnline ?? DateTime.now())))}",
                style: TextStyle(fontSize: 12, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.report_gmailerrorred_outlined),
          onPressed: () {
            showCupertinoModalPopup<void>(
              context: context,
              builder: (context) => CupertinoActionSheet(
                title: Text("Choose Action"),
                actions: [
                  CupertinoActionSheetAction(
                    onPressed: () {
                      ReportedUser userreported = ReportedUser(
                        date: DateTime.now(),
                        reportedByUid: widget.bot.uid,
                        reportedUid: user.uid,
                      );
                      DatabaseService.reportUsers(userreported, context);
                      Navigator.pop(context);
                    },
                    child: Text("Report"),
                    isDestructiveAction: true,
                  ),
                  if (!chatRoom.isBlocked)
                    CupertinoActionSheetAction(
                      onPressed: () async {
                        await ChatRoomRepository.blockChatRoom(
                          chatRoom.roomId,
                          widget.bot.uid,
                        );
                        getUser();
                        Navigator.pop(context);
                      },
                      child: Text("Block"),
                      isDestructiveAction: true,
                    ),
                  // else
                  //   CupertinoActionSheetAction(
                  //     child: SizedBox(),
                  //     onPressed: () {},
                  //   ),
                ],
                cancelButton: CupertinoActionSheetAction(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Cancel"),
                ),
              ),
            );
          },
        ),
        SizedBox(width: kDefaultPadding / 2),
      ],
    );
  }
}

class BotMessage extends StatefulWidget {
  final MessageModel message;
  final String? picUrl;
  final String? docId;
  final String botId;

  const BotMessage({
    required this.message,
    this.picUrl,
    this.docId,
    required this.botId,
  });

  @override
  _BotMessageState createState() => _BotMessageState();
}

class _BotMessageState extends State<BotMessage> {
  @override
  Widget build(BuildContext context) {
    bool isSender = widget.message.uid == widget.botId;

    if (!isSender && widget.message.seen == false) {
      ChatService.updateSeen(widget.docId!, {"seen": true});
    }

    return Padding(
      padding: const EdgeInsets.only(top: kDefaultPadding),
      child: Row(
        mainAxisAlignment: isSender
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isSender) ...[
            // CircleAvatar(
            //   radius: 12,
            //   backgroundImage: NetworkImage(widget.picUrl ?? ""),
            // ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(shape: BoxShape.circle),
              clipBehavior: Clip.antiAlias,
              child: ReactiveProfileImage(
                imagePath: widget.picUrl ?? '',
                gender: 'male',
                width: 24,
                height: 24,
              ),
            ),
            SizedBox(width: kDefaultPadding / 2),
          ],
          TextMessage(
            message: widget.message.text,
            imagePath: widget.message.imagePath ?? [],
            isSender: isSender,
            time: widget.message.date,
          ),
          // if (isSender) MessageStatusDot(seen: widget.message.seen),
        ],
      ),
    );
  }
}

class MessageStatusDot extends StatelessWidget {
  final bool seen;

  const MessageStatusDot({super.key, required this.seen});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Icon(
        seen ? Icons.done_all : Icons.check,
        size: 16,
        color: Color(0xFF3487B9),
      ),
    );
  }
}
