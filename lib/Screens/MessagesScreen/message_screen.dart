import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/svg.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:viora/Screens/ProfileScreen/new_profile_view.dart';

// Hooks

// Models & Services (existing)
import 'package:viora/models/UserDetails.dart';
import 'package:viora/models/ChatRoom.dart';
import 'package:viora/models/Message.dart';
import 'package:viora/Services/SubscriptionService.dart';
import 'package:viora/Services/UserProvider.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/Services/ImageUploadService.dart';
import 'package:viora/Services/dialogs.dart';
import 'package:viora/constants.dart';
import 'package:viora/size_config.dart';
import '../../Services/CustomHooksMessages.dart';
import '../../Services/MessageAndChatRepository.dart';
import '../../Services/MessageAndCoinValidator.dart';
// import '../GemsScreen/gemsScreen.dart'; // Commented: replaced by PaymentScreen
import '../PaymentScreen/payment_screen.dart';
import '../ProfileScreen/profileScreen.dart';
import 'components/message.dart';

/// Main messaging screen using Flutter Hooks for state management
///
/// This widget demonstrates separation of concerns:
/// - UI state is managed via hooks (useState, useEffect)
/// - Business logic is in separate validator classes
/// - Backend operations are in repository classes
class MessagesScreen extends HookWidget {
  final String uId;

  const MessagesScreen({Key? key, required this.uId}) : super(key: key);

  static String routeName = "/messagesScreen";

  @override
  Widget build(BuildContext context) {
    // HOOKS: UI State Management
    // useState replaces StatefulWidget's state variables
    final messageCtr = useTextEditingController();

    // Custom hook: Manages user data fetching and real-time updates
    final userState = useUserData(uId);

    // Custom hook: Manages chat room setup and monitoring
    final chatRoomState = useChatRoom(uId, userState.user);

    // Custom hook: Handles typing indicator logic
    final typingState = useTypingIndicator(
      messageCtr,
      chatRoomState.chatRoom?.roomId,
    );

    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final imageEligibilityFuture = useMemoized(
      () => myUid.isEmpty
          ? Future.value(false)
          : SubscriptionService.canSendImagesForUser(myUid),
      [myUid],
    );
    final imageEligibility = useFuture(imageEligibilityFuture);

    // useEffect: Setup lifecycle management (replaces initState/dispose)
    useEffect(() {
      // Lifecycle observer for app state changes
      WidgetsBinding.instance.addObserver(_AppLifecycleObserver());

      // Cleanup when widget is disposed (replaces dispose())
      return () {
        WidgetsBinding.instance.removeObserver(_AppLifecycleObserver());
        DatabaseService.updateField({"isTyping": ""});
      };
    }, []);

    // Loading state
    if (userState.isLoading || chatRoomState.isLoading) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: kPrimaryColor,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Error state
    if (userState.user == null || chatRoomState.chatRoom == null) {
      print(
        "vinay userState.user null ${userState.user == null} or chatRoomState null ${chatRoomState.chatRoom == null}",
      );
      return Scaffold(
        appBar: AppBar(backgroundColor: kPrimaryColor),
        body: const Center(child: Text('Error loading chat')),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(context, userState.user!, chatRoomState.chatRoom!),
      body: Column(
        children: [
          // Warning banner
          _buildWarningBanner(context),

          // Messages list
          Expanded(
            child: _buildMessagesList(
              context,
              chatRoomState.chatRoom!,
              userState.user!,
            ),
          ),

          // Message input area
          _buildMessageInput(
            context,
            chatRoomState.chatRoom!,
            userState.user!,
            messageCtr,
            typingState.showSendButton,
            imageEligibility.data == true,
          ),
        ],
      ),
    );
  }

  /// Builds the warning banner at the top
  Widget _buildWarningBanner(BuildContext context) {
    return Container(
      color: Colors.orangeAccent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text("Don't Ask/Send Money"),
          ),
          const Spacer(),
          _buildCoinsDisplay(context),
        ],
      ),
    );
  }

  /// Displays coin balance for male users
  Widget _buildCoinsDisplay(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    if (userProvider.userDetails.gender != "Male") {
      return const SizedBox();
    }

    return GestureDetector(
      onTap: () {
        PersistentNavBarNavigator.pushNewScreen(
          context,
          // screen: GemsScreen(), // Commented: use PaymentScreen
          screen: PaymentScreen(),
          withNavBar: false,
          pageTransitionAnimation: PageTransitionAnimation.cupertino,
        );
      },
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              "Coins : ${Provider.of<UserProvider>(context, listen: true).userDetails.coins}",
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SvgPicture.asset(
              "assets/svg/coins.svg",
              color: Colors.black,
              width: getProportionateScreenWidth(20),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the messages list using FirestoreListView
  Widget _buildMessagesList(
    BuildContext context,
    ChatRoom chatRoom,
    UserDetails user,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kDefaultPadding),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).requestFocus(FocusNode()),
        child: FirestoreListView(
          query: FirebaseFirestore.instance
              .collection('Messages')
              .where("roomId", isEqualTo: chatRoom.roomId)
              .orderBy('date', descending: true),
          itemBuilder: (context, documentSnapshots) {
            final data = documentSnapshots.data();
            return Message(
              docId: documentSnapshots.id,
              message: MessageModel.fromJson(data),
              picUrl: user.images!.isEmpty
                  ? user.gender == "Male"
                        ? kMaleUrl
                        : kFemaleUrl
                  : user.images![0],
              gender: user.gender ?? "male",
            );
          },
          reverse: true,
          emptyBuilder: (context) =>
              const Center(child: Text("Say Hi to start conversation")),
          padding: EdgeInsets.all(getProportionateScreenWidth(5)),
          shrinkWrap: true,
          pageSize: 5,
          loadingBuilder: (context) =>
              const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  /// Builds the message input area with send button
  Widget _buildMessageInput(
    BuildContext context,
    ChatRoom chatRoom,
    UserDetails user,
    TextEditingController messageCtr,
    bool showSendButton,
    bool firestoreAllowsPremiumImages,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: kDefaultPadding,
        vertical: kDefaultPadding / 2,
      ),
      decoration: BoxDecoration(
        color: Colors.transparent,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, 4),
            blurRadius: 32,
            color: const Color(0xFF087949).withAlpha(24),
          ),
        ],
      ),
      child: chatRoom.isBlocked
          ? _buildBlockedState(context, chatRoom)
          : _buildActiveInputState(
              context,
              chatRoom,
              user,
              messageCtr,
              showSendButton,
              firestoreAllowsPremiumImages,
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
          if (chatRoom.blockedBy == FirebaseAuth.instance.currentUser!.uid)
            ElevatedButton(
              onPressed: () async {
                await ChatRoomRepository.unblockChatRoom(chatRoom.roomId, '');
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

  /// Shows active input state with image and send buttons
  Widget _buildActiveInputState(
    BuildContext context,
    ChatRoom chatRoom,
    UserDetails user,
    TextEditingController messageCtr,
    bool showSendButton,
    bool firestoreAllowsPremiumImages,
  ) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    return SafeArea(
      child: Row(
        children: [
          // Image upload button
          _buildImageButton(
            context,
            chatRoom,
            user,
            userProvider,
            firestoreAllowsPremiumImages,
          ),

          // Text input field
          Expanded(child: _buildTextField(messageCtr)),

          // Send button (shown when text is entered)
          if (showSendButton)
            _buildSendButton(context, chatRoom, user, messageCtr, userProvider),
        ],
      ),
    );
  }

  /// Image upload button with lock indicator for unpaid male users
  Widget _buildImageButton(
    BuildContext context,
    ChatRoom chatRoom,
    UserDetails user,
    UserProvider userProvider,
    bool firestoreAllowsPremiumImages,
  ) {
    // Strict ownership: premium/elite from Firestore (webhook), not RevenueCat CustomerInfo
    final canSendImage = CoinValidator.canSendImage(
      userProvider.userDetails,
      firestoreAllowsPremiumImages,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => _handleImageUpload(
            context,
            chatRoom,
            user,
            userProvider,
            canSendImage,
          ),
          child: Container(
            padding: EdgeInsets.all(getProportionateScreenWidth(12)),
            height: getProportionateScreenWidth(46),
            width: getProportionateScreenWidth(46),
            decoration: const BoxDecoration(
              color: kPrimaryColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.image, color: Colors.white),
          ),
        ),
        // Lock indicator for restricted users
        if (!canSendImage && userProvider.userDetails.gender == "Male")
          const Positioned(
            right: -4,
            top: -8,
            child: Icon(Icons.lock, color: Colors.black),
          ),
      ],
    );
  }

  /// Text input field
  Widget _buildTextField(TextEditingController messageCtr) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: kDefaultPadding * 0.75),
        decoration: BoxDecoration(
          color: kPrimaryColor.withOpacity(0.10),
          borderRadius: BorderRadius.circular(40),
        ),
        child: TextField(
          controller: messageCtr,
          keyboardType: TextInputType.multiline,
          minLines: 1,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: "Type message",
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }

  /// Send button with coin check for male users
  Widget _buildSendButton(
    BuildContext context,
    ChatRoom chatRoom,
    UserDetails user,
    TextEditingController messageCtr,
    UserProvider userProvider,
  ) {
    return GestureDetector(
      onTap: () =>
          _handleSendMessage(context, chatRoom, user, messageCtr, userProvider),
      child: Container(
        padding: EdgeInsets.all(getProportionateScreenWidth(12)),
        height: getProportionateScreenWidth(46),
        width: getProportionateScreenWidth(46),
        decoration: const BoxDecoration(
          color: kPrimaryColor,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.send, color: Colors.white),
      ),
    );
  }

  /// Handles image upload logic - delegates to business logic and repository
  void _handleImageUpload(
    BuildContext context,
    ChatRoom chatRoom,
    UserDetails user,
    UserProvider userProvider,
    bool canSendImage,
  ) {
    if (userProvider.userDetails.gender == "Female") {
      // ImageUploadService.sendImageMessage(context, chatRoom.roomId, user);
      return;
    }

    // Business Logic: Validate coins and subscription
    if (!canSendImage) {
      if (userProvider.userDetails.coins! <= 0) {
        CustomDialog.outOfCoinsDialog(context);
      } else {
        CustomDialog.buyImagePackDialog(context);
      }
      return;
    }

    // ImageUploadService.sendImageMessage(context, chatRoom.roomId, user);
  }

  /// Handles message sending - uses business logic validation and repository
  Future<void> _handleSendMessage(
    BuildContext context,
    ChatRoom chatRoom,
    UserDetails user,
    TextEditingController messageCtr,
    UserProvider userProvider,
  ) async {
    // Business Logic: Check if user has coins (male only)
    if (userProvider.userDetails.gender == "Male" &&
        userProvider.userDetails.coins! <= 0) {
      FocusScope.of(context).requestFocus(FocusNode());
      CustomDialog.outOfCoinsDialog(context);
      return;
    }

    final messageText = messageCtr.text.trim();
    messageCtr.clear();

    // Business Logic: Validate message for spam/contact info
    final validationResult = MessageValidator.validateMessage(messageText);

    if (!validationResult.isValid) {
      // Repository: Handle spam reporting
      await MessageRepository.handleSpamMessage(
        messageText,
        validationResult.reason ?? 'Unknown',
      );

      AwesomeDialog(
        context: context,
        dialogType: DialogType.error,
        animType: AnimType.bottomSlide,
        title: 'This action is not allowed',
        desc: 'Exchanging Contact details is not allowed',
      ).show();

      return;
    }

    // Clear typing indicator
    DatabaseService.updateField({"isTyping": ""});

    if (messageText.isEmpty) return;

    // Repository: Send message
    await MessageRepository.sendMessage(
      context: context,
      chatRoom: chatRoom,
      receiver: user,
      messageText: messageText,
      currentUserName: userProvider.userDetails.name!,
    );

    messageCtr.clear();
  }

  /// Builds the app bar with user info and actions
  AppBar _buildAppBar(
    BuildContext context,
    UserDetails user,
    ChatRoom chatRoom,
  ) {
    return AppBar(
      iconTheme: const IconThemeData(color: Colors.white),
      automaticallyImplyLeading: false,
      backgroundColor: kPrimaryColor,
      title: Row(
        children: [
          const BackButton(),
          GestureDetector(
            onTap: () {
              PersistentNavBarNavigator.pushNewScreen(
                context,
                screen: NewProfileView(uid: user.uid, canPop: true),
                withNavBar: false,
                pageTransitionAnimation: PageTransitionAnimation.cupertino,
              );
            },
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(30)),
              child: CachedNetworkImage(
                imageUrl: user.images!.isEmpty
                    ? user.gender == "Male"
                          ? kMaleUrl
                          : kFemaleUrl
                    : user.images![0],
                height: 45,
                width: 45,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: kDefaultPadding * 0.75),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.name!,
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
              Text(
                user.isTyping == chatRoom.roomId
                    ? "Typing..."
                    : user.isOnline!
                    ? "Online"
                    : "Active ${timeago.format(DateTime.now().subtract(DateTime.now().difference(user.lastOnline!)))}",
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (uId != "Yl5RALFSJdOke2wgRDZp")
          IconButton(
            icon: const Icon(Icons.report_gmailerrorred_outlined),
            onPressed: () => _showReportActions(context, chatRoom, user),
          ),
        const SizedBox(width: kDefaultPadding / 2),
      ],
    );
  }

  /// Shows report and block actions
  void _showReportActions(
    BuildContext context,
    ChatRoom chatRoom,
    UserDetails user,
  ) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text("Actions"),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            onPressed: () async {
              // Repository: Report user
              await MessageRepository.reportUser(user.uid, context);
              Navigator.pop(context);
            },
            isDestructiveAction: true,
            child: const Text("Report"),
          ),
          if (!chatRoom.isBlocked)
            CupertinoActionSheetAction(
              onPressed: () async {
                // Repository: Block chat room
                await ChatRoomRepository.blockChatRoom(chatRoom.roomId, "");
                Navigator.pop(context);
              },
              isDestructiveAction: true,
              child: const Text("Block"),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
      ),
    );
  }
}

/// App lifecycle observer for handling typing state cleanup
class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      DatabaseService.updateField({"isTyping": ""});
    }
  }
}
