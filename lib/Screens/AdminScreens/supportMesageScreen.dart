import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:iconsax/iconsax.dart';
import 'package:viora/Screens/AdminScreens/AdminProfileView.dart';
import 'package:viora/Screens/MessagesScreen/components/text_message.dart';
import 'package:viora/Services/ChatService.dart';
import 'package:viora/Services/ImageUploadService.dart';
import 'package:viora/Services/NotificationService.dart';
import 'package:viora/components/admin_support_dialog.dart';
import 'package:viora/components/reusable_dialog.dart';
import 'package:viora/components/title_message_list.dart';
import 'package:viora/models/ChatRoom.dart';
import 'package:viora/models/Message.dart';
import 'package:viora/models/SupportModels.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:viora/utils/constatnts/colors.dart';
import 'package:viora/utils/helpers/admin_support_helper.dart';
import 'package:viora/utils/helpers/image_helper.dart';

import '../../constants.dart';
import '../../size_config.dart';

class SupportMessageScreen extends StatefulHookWidget {
  final String uId;

  const SupportMessageScreen({super.key, required this.uId});

  @override
  SupportMessageScreenState createState() => SupportMessageScreenState();
}

class SupportMessageScreenState extends State<SupportMessageScreen> {
  late bool isLoading;
  late UserDetails user;
  TextEditingController messageCtr = TextEditingController();

  late ChatRoom chatRoom;

  @override
  void initState() {
    super.initState();
    isLoading = true;
    getUser();
  }

  Future<void> getUser() async {
    FirebaseFirestore.instance
        .collection("Users")
        .doc(widget.uId)
        .snapshots()
        .listen((event) {
          user = UserDetails.fromJson(event.data() as Map<String, dynamic>);
          if (mounted) {
            setState(() {});
          }
        });

    await checkRoom();
  }

  Future<void> checkRoom() async {
    String uid = "support";
    var user2 = uid;
    var user1 = widget.uId;
    var path = user1.codeUnitAt(0) < user2.codeUnitAt(0)
        ? "${user1}_$user2"
        : "${user2}_$user1";

    var docRef = FirebaseFirestore.instance
        .collection("SupportChatRooms")
        .doc(path);

    var docSnap = await docRef.get();

    if (docSnap.exists) {
      chatRoom = ChatRoom.fromJson(docSnap.data() as Map<String, dynamic>);
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
        users: ["support"],
      );

      await ChatService.addSupportChatRoom(newChatRoom, context);
      await checkRoom();
    }
  }

  /// Handles image upload logic - delegates to business logic and repository
  void _handleImageUpload(
    BuildContext context,
    ChatRoom chatRoom,
    UserDetails user,
  ) {
    ImageUploadService.sendMultipleSupportImagesAdmin(
      context,
      chatRoom.roomId,
      user,
    );
    return;
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
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kDefaultPadding,
                    ),
                    child: GestureDetector(
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: RefreshIndicator(
                        onRefresh: () async {
                          refreshKey.value = DateTime.now(); // triggers refresh
                        },
                        child: FirestoreQueryBuilder(
                          key: ValueKey(refreshKey.value),
                          query: FirebaseFirestore.instance
                              .collection('SupportMessages')
                              .where("roomId", isEqualTo: chatRoom.roomId)
                              .orderBy('date', descending: true),
                          pageSize: 5,
                          builder: (context, snapshot, _) {
                            if (snapshot.isFetching) {
                              return Center(child: CircularProgressIndicator());
                            }
                            if (snapshot.hasError) {
                              return Center(
                                child: Text('Error: ${snapshot.error}'),
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
                                final message = SupportMessageModel.fromJson(
                                  data,
                                );

                                if (message.messageType.toLowerCase() ==
                                    'title') {
                                  if (message.text == "New Issue Reported") {
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          height: getProportionateScreenHeight(
                                            36,
                                          ),
                                        ),
                                        TitleMessageList(message: message.text),
                                      ],
                                    );
                                  }
                                  return TitleMessageList(
                                    message: message.text,
                                  );
                                }
                                return SupportMessage(
                                  docId: snapshot.docs[index].id,
                                  message: message,
                                  picUrl: user.images!.isEmpty
                                      ? null
                                      : user.images![0],
                                  gender: user.gender ?? "male",
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                buildMessageInput(),
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
            color: Color(0xFF087949).withAlpha(20),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: getProportionateScreenHeight(52),
                padding: EdgeInsets.fromLTRB(kDefaultPadding * 0.75, 0, 6, 0),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: messageCtr,
                        keyboardType: TextInputType.multiline,
                        minLines: 1,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText: "Type message",
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    _buildImageButton(context, chatRoom, user),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () async {
                String messageText = messageCtr.text.trim();
                if (messageText.isNotEmpty) {
                  messageCtr.clear();
                  MessageModel message = MessageModel(
                    seen: false,
                    receiver: '',
                    date: DateTime.now(),
                    uid: "support",
                    text: messageText,
                    roomId: chatRoom.roomId,
                  );

                  ChatService.sendSupportMessage(message, context);

                  setState(() {});

                  NotificationService.sendNotification(
                    user.fcmToken,
                    "Support Message Response",
                    messageText,
                    '',
                  );
                }
              },
              child: Container(
                height: getProportionateScreenWidth(46),
                width: getProportionateScreenWidth(46),
                decoration: BoxDecoration(
                  color: kPrimaryColor,
                  shape: BoxShape.circle,
                ),
                child: Center(child: Icon(Icons.send, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageButton(
    BuildContext context,
    ChatRoom chatRoom,
    UserDetails user,
  ) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => _handleImageUpload(context, chatRoom, user),
          child: Container(
            height: getProportionateScreenWidth(40),
            width: getProportionateScreenWidth(40),
            decoration: BoxDecoration(
              color: kPrimaryColor.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: const Icon(Iconsax.gallery5, color: AppColors.purple),
            ),
          ),
        ),
      ],
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
                screen: AdminProfileView(uid: user.uid),
                withNavBar: false,
                pageTransitionAnimation: PageTransitionAnimation.cupertino,
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(30)),
              child: ReactiveProfileImage(
                imagePath: user.images!.isEmpty ? '' : user.images![0],
                gender: user.gender ?? 'male',
                width: 45,
                height: 45,
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
                user.name ?? "'name",
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
              Text(
                user.isTyping == chatRoom.roomId
                    ? "Typing..."
                    : (user.isOnline == true ? true : false)
                    ? "Online"
                    : "Active ${timeago.format(DateTime.now().subtract(DateTime.now().difference(user.lastOnline ?? DateTime.now())))}",
                style: TextStyle(fontSize: 12, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
      actions: [
        GestureDetector(
          onTap: () async {
            await AdminSupportDialog.show(
              context,
              "Change Chat Room Status",
              onNew: () async {
                await FirebaseFirestore.instance
                    .collection('SupportChatRooms')
                    .doc(chatRoom.roomId)
                    .update({'status': 'new'});
                SupportMessageModel titleMessage = SupportMessageModel(
                  seen: false,
                  roomId: chatRoom.roomId,
                  date: DateTime.now(),
                  uid: "support",
                  text: "Your issue(s) are marked New",
                  messageType: 'title',
                );
                await ChatService.sendSupportMessageEnhanced(
                  titleMessage,
                  context,
                );
                Navigator.of(context).pop();
              },
              onInProgress: () async {
                await FirebaseFirestore.instance
                    .collection('SupportChatRooms')
                    .doc(chatRoom.roomId)
                    .update({'status': 'in-progress'});
                SupportMessageModel titleMessage = SupportMessageModel(
                  seen: false,
                  roomId: chatRoom.roomId,
                  date: DateTime.now(),
                  uid: "support",
                  text: "Your issue(s) are In Progress",
                  messageType: 'title',
                );
                await ChatService.sendSupportMessageEnhanced(
                  titleMessage,
                  context,
                );
                Navigator.of(context).pop();
              },
              onResolved: () async {
                await FirebaseFirestore.instance
                    .collection('SupportChatRooms')
                    .doc(chatRoom.roomId)
                    .update({'status': 'resolved'});
                SupportMessageModel titleMessage = SupportMessageModel(
                  seen: false,
                  roomId: chatRoom.roomId,
                  date: DateTime.now(),
                  uid: "support",
                  text: "Your issue(s) are Resolved",
                  messageType: 'title',
                );
                await ChatService.sendSupportMessageEnhanced(
                  titleMessage,
                  context,
                );
                Navigator.of(context).pop();
              },
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: chatRoom.status != null
                  ? AdminSupportHelper().color(chatRoom.status ?? "no-status")
                  : AppColors.lavendar,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              chatRoom.status != null
                  ? AdminSupportHelper().status(chatRoom.status ?? "no-status")
                  : "No status",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
        ),
        SizedBox(width: kDefaultPadding / 2),
      ],
    );
  }
}

class SupportMessage extends StatefulWidget {
  final SupportMessageModel message;
  final String? picUrl;
  final String? docId;
  final String? gender;

  const SupportMessage({
    required this.message,
    this.picUrl,
    this.docId,
    this.gender,
  });

  @override
  _SupportMessageState createState() => _SupportMessageState();
}

class _SupportMessageState extends State<SupportMessage> {
  @override
  Widget build(BuildContext context) {
    bool isSender = widget.message.uid == "support";

    if (widget.message.uid != "support" && widget.message.seen == false) {
      ChatService.updateSupportSeen(widget.docId!, {"seen": true});
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
            ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              child: ReactiveProfileImage(
                imagePath: widget.picUrl ?? "",
                width: 24,
                height: 24,
                gender: widget.gender ?? "male",
              ),
            ),
            SizedBox(width: kDefaultPadding / 2),
          ],
          TextMessage(
            message: widget.message.text,
            isSender: isSender,
            time: widget.message.date,
            imagePath: widget.message.imageUrls,
            isSupportMessage: true,
          ),
          // if (isSender) MessageStatusDot(seen: widget.message.seen),
        ],
      ),
    );
  }
}
