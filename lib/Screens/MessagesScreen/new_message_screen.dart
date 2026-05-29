import 'dart:async';

import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:iconsax/iconsax.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:viora/Screens/PaymentScreen/payment_screen.dart';
import 'package:viora/Screens/ProfileScreen/new_profile_view.dart';
import 'package:viora/Services/AppConfigService.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/components/report_block_dialog.dart';
import 'package:viora/components/reusable_dialog.dart';
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
import 'package:viora/utils/constatnts/colors.dart';
import 'package:viora/utils/helpers/image_helper.dart';
import 'package:viora/utils/helpers/message_helper.dart';
import '../../Services/CustomHooksMessages.dart';
import '../../Services/MessageAndChatRepository.dart';
import '../../Services/MessageAndCoinValidator.dart';
import 'components/message.dart';

/// Main messaging screen using Flutter Hooks for state management
///
/// This widget demonstrates separation of concerns:
/// - UI state is managed via hooks (useState, useEffect)
/// - Business logic is in separate validator classes
/// - Backend operations are in repository classes
class NewMessagesScreen extends HookWidget {
  final String uId;

  const NewMessagesScreen({super.key, required this.uId});

  static String routeName = "/newMessagesScreen";

  @override
  Widget build(BuildContext context) {
    final globals = Globals.of(context);
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

    Future<void> onEnterScreen() async {
      await MessageHelper.updateLastDateIfNeeded();
    }

    // useEffect: Setup lifecycle management (replaces initState/dispose)
    useEffect(() {
      // Lifecycle observer for app state changes
      WidgetsBinding.instance.addObserver(_AppLifecycleObserver());

      onEnterScreen();

      // Cleanup when widget is disposed (replaces dispose())
      return () {
        WidgetsBinding.instance.removeObserver(_AppLifecycleObserver());
        DatabaseService.updateField({"isTyping": ""});
      };
    }, []);

    // Loading state
    if (userState.isLoading || chatRoomState.isLoading) {
      return Scaffold(body: const Center(child: CircularProgressIndicator()));
    }

    // Error state
    if (userState.user == null || chatRoomState.chatRoom == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: kPrimaryColor),
        body: const Center(child: Text('Error loading chat')),
      );
    }

    final userDetails = useListenable(globals.prefs.userDetails);
    final currentUser = userDetails.value;

    final user = userState.user!;
    final chatRoom = chatRoomState.chatRoom!;
    final isActiveSubscription = useState<bool>(false);
    // Listen to auth state so current user id updates dynamically
    final authSnapshot = useStream(FirebaseAuth.instance.authStateChanges());
    final currentUid = authSnapshot.data?.uid;

    // canMessage: null = loading, true = allowed, false = not allowed
    final canMessage = useState<bool?>(null);

    // Compute whether current user can message this `user` (recipient)
    useEffect(() {
      canMessage.value = null;
      if (currentUid == null) {
        canMessage.value = false;
        return null;
      }

      var cancelled = false;
      () async {
        try {
          final hasLiked = await hasUserLikedMyProfile(user.uid, currentUid);
          final permission = user.messagePermission?.toLowerCase();
          final allowed = hasLiked || permission == null || permission == 'all';
          if (!cancelled) canMessage.value = allowed;
        } catch (e) {
          if (!cancelled) canMessage.value = false;
        }
      }();

      return () {
        cancelled = true;
      };
    }, [currentUid, user.uid, user.messagePermission]);

    useEffect(() {
      if (currentUid == null || currentUid.isEmpty) {
        isActiveSubscription.value = false;
        return null;
      }

      bool disposed = false;
      StreamSubscription? subscriptionSub;

      Future<void> checkSubscription() async {
        try {
          final freeFeatureDoc = await FirebaseFirestore.instance
              .collection('Subscriptions')
              .doc('freeFeatures')
              .get();

          final data = freeFeatureDoc.data();

          final genderKey = currentUser?.gender?.toLowerCase() == "female"
              ? "female"
              : "male";

          final genderData = data?[genderKey] as Map<String, dynamic>?;
          final isEnabled = genderData?['isEnable'] as bool? ?? false;

          if (isEnabled) {
            final features = genderData?['features'] as Map<String, dynamic>?;
            final imageView = features?['image_view'] as Map<String, dynamic>?;

            final bool isFreeImageViewEnabled = imageView?['enabled'] == true;

            if (disposed) return;

            if (isFreeImageViewEnabled) {
              isActiveSubscription.value = true;
              return;
            }
          }

          final subscriptionRef = FirebaseFirestore.instance
              .collection('Users')
              .doc(currentUid)
              .collection('Subscription')
              .doc('current');

          subscriptionSub = subscriptionRef.snapshots().listen(
            (snapshot) async {
              if (!snapshot.exists) {
                isActiveSubscription.value = false;
                return;
              }

              final displayInfo =
                  await SubscriptionService.getSubscriptionDisplayInfo(
                    currentUid,
                    forceRefresh: true,
                  );

              final bool isActive = displayInfo?.isActive ?? false;
              final features = displayInfo?.entitlementFeatures;
              final bool hasImageView =
                  features?.isFeatureEnabled('image_view') ?? false;

              if (!disposed) {
                isActiveSubscription.value = isActive && hasImageView;
              }
            },
            onError: (error) {
              if (error is FirebaseException &&
                  error.code == 'permission-denied') {
                isActiveSubscription.value = false;
                return;
              }

              debugPrint('Subscription listener error: $error');
            },
          );
        } catch (e) {
          debugPrint('Error checking subscription: $e');

          if (!disposed) {
            isActiveSubscription.value = false;
          }
        }
      }

      checkSubscription();

      return () {
        disposed = true;
        subscriptionSub?.cancel();
      };
    }, [currentUid, currentUser?.gender]);

    useEffect(() {
      return null;
    }, []);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: getProportionateScreenHeight(68),
        automaticallyImplyLeading: false,
        scrolledUnderElevation: 0,
        shadowColor: Colors.white,
        backgroundColor: Colors.white,
        title: Row(
          children: [
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
              },
              child: Icon(Icons.arrow_back, color: Colors.black),
            ),
            SizedBox(width: getProportionateScreenWidth(8)),
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
                borderRadius: BorderRadiusGeometry.circular(21),
                child: ReactiveProfileImage(
                  imagePath: user.images?.isNotEmpty == true
                      ? user.images![0]
                      : '',
                  gender: user.gender ?? "male",
                  width: getProportionateScreenWidth(42),
                  height: getProportionateScreenWidth(42),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name!,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      user.isTyping == chatRoom.roomId
                          ? "Typing..."
                          : user.isOnline!
                          ? "Active"
                          : "Active ${timeago.format(DateTime.now().subtract(DateTime.now().difference(user.lastOnline!)))}",
                      style: TextStyle(
                        fontSize: 11,
                        color: user.isOnline! ? Colors.green : Colors.black,
                      ),
                    ),
                    SizedBox(width: getProportionateScreenWidth(4)),
                    Container(
                      width: getProportionateScreenWidth(8),
                      height: getProportionateScreenWidth(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: user.isOnline! ? Colors.green : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (uId != "Yl5RALFSJdOke2wgRDZp")
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded, color: Colors.black),
              onPressed: () {
                ReportBlockDialog.show(
                  context,
                  onReport: () async {
                    // Report user for inappropriate behavior
                    await MessageRepository.reportUser(user.uid, context);
                    Navigator.pop(context);
                  },
                  onBlock: () async {
                    // Repository: Block chat room
                    await ChatRoomRepository.blockChatRoom(chatRoom.roomId, "");
                  },
                  chatRoom: chatRoom,
                  user: user,
                );
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/backgrounds/interactions.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          Column(
            children: [
              Container(
                width: double.infinity,
                height: 1,
                color: Colors.grey.shade300,
              ),
              // Messages list
              Expanded(
                child: _buildMessagesList(
                  context,
                  chatRoomState.chatRoom!,
                  userState.user!,
                ),
              ),

              // Message input area (passes canMessage to control UI)
              _buildMessageInput(
                context,
                chatRoomState.chatRoom!,
                userState.user!,
                messageCtr,
                typingState.showSendButton,
                isActiveSubscription,
                canMessage,
              ),
            ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).requestFocus(FocusNode()),
        child: FirestoreListView(
          query: FirebaseFirestore.instance
              .collection('Messages')
              .where("roomId", isEqualTo: chatRoom.roomId)
              .orderBy('date', descending: true),
          itemBuilder: (context, documentSnapshots) {
            final data = documentSnapshots.data();
            final currentUserGender =
                Provider.of<UserProvider>(
                  context,
                  listen: false,
                ).userDetails.gender?.toLowerCase() ??
                'male';
            return Message(
              docId: documentSnapshots.id,
              message: MessageModel.fromJson(data),
              picUrl: user.images!.isEmpty
                  ? user.gender?.toLowerCase() == "Male"
                        ? AppConfigService.maleImageUrl
                        : AppConfigService.femaleImageUrl
                  : user.images![0],
              gender: currentUserGender,
            );
          },
          reverse: true,
          cacheExtent: 1200,
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
    ValueNotifier<bool> isActiveSubscription,
    ValueNotifier<bool?> canMessage,
  ) {
    // Treat `canMessage == false` similar to blocked state
    if (chatRoom.isBlocked) {
      return _buildBlockedState(context, chatRoom);
    }

    if (canMessage.value == false) {
      return _buildLikedOnlyMessage();
    }

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
            color: const Color(0xFF087949).withAlpha(20),
          ),
        ],
      ),
      child: _buildActiveInputState(
        context,
        chatRoom,
        user,
        messageCtr,
        showSendButton,
        isActiveSubscription,
        canMessage,
      ),
    );
  }

  /// Shows blocked chat room state
  Widget _buildBlockedState(BuildContext context, ChatRoom chatRoom) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: GestureDetector(
          onTap: (chatRoom.blockedBy == FirebaseAuth.instance.currentUser!.uid)
              ? () async {
                  await ChatRoomRepository.unblockChatRoom(chatRoom.roomId, '');
                }
              : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(0xFFEF4D50),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.block, color: Colors.white),
                    SizedBox(width: getProportionateScreenWidth(8)),
                    const Text(
                      "User is Blocked",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                // const Spacer(),
                SizedBox(height: getProportionateScreenHeight(2)),
                if (chatRoom.blockedBy ==
                    FirebaseAuth.instance.currentUser!.uid)
                  const Text(
                    "Tap here to unblock.",
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      color: Color(0xFFF8F860),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLikedOnlyMessage() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: GestureDetector(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.block, color: Colors.white),
                SizedBox(width: getProportionateScreenWidth(8)),
                Expanded(
                  child: const Text(
                    "This profile allows chats only with matched or liked profiles",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
    ValueNotifier<bool> isActiveSubscription,
    ValueNotifier<bool?> canMessage,
  ) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    return SafeArea(
      child: Row(
        children: [
          // Text input field
          Expanded(
            child: _buildTextField(
              messageCtr,
              context,
              chatRoom,
              user,
              userProvider,
              isActiveSubscription,
            ),
          ),
          _buildSendButton(
            context,
            chatRoom,
            user,
            messageCtr,
            userProvider,
            isActiveSubscription,
            canMessage,
          ),
        ],
      ),
    );
  }

  /// Text input field
  Widget _buildTextField(
    TextEditingController messageCtr,
    BuildContext context,
    ChatRoom chatRoom,
    UserDetails user,
    UserProvider userProvider,
    ValueNotifier<bool> isActiveSubscription,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: Container(
        height: getProportionateScreenHeight(58),
        padding: const EdgeInsets.fromLTRB(kDefaultPadding * 0.75, 0, 6, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Color(0xFFF9B2CA)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                textInputAction: TextInputAction.done,
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
            SizedBox(width: getProportionateScreenWidth(2)),
            _buildImageButton(
              context,
              chatRoom,
              user,
              userProvider,
              isActiveSubscription,
            ),
          ],
        ),
      ),
    );
  }

  /// Image upload button with lock indicator for unpaid male users
  Widget _buildImageButton(
    BuildContext context,
    ChatRoom chatRoom,
    UserDetails user,
    UserProvider userProvider,
    ValueNotifier<bool> isActiveSubscription,
  ) {
    final canSendImage =
        isActiveSubscription.value &&
        (((userProvider.userDetails.coins ?? 0) > 0) ||
            userProvider.userDetails.coins == -1);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => _handleImageUpload(
            context,
            chatRoom,
            user,
            userProvider,
            isActiveSubscription,
          ),
          child: Container(
            padding: EdgeInsets.all(getProportionateScreenWidth(12)),
            height: getProportionateScreenWidth(48),
            width: getProportionateScreenWidth(48),
            decoration: BoxDecoration(
              color: kPrimaryColor.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(Iconsax.gallery5, color: AppColors.purple),
          ),
        ),
        // Lock indicator for restricted users
        if (!canSendImage)
          const Positioned(
            right: 4,
            top: 4,
            child: Icon(Icons.lock, size: 16, color: Colors.black),
          ),
      ],
    );
  }

  /// Send button with coin check for male users
  Widget _buildSendButton(
    BuildContext context,
    ChatRoom chatRoom,
    UserDetails user,
    TextEditingController messageCtr,
    UserProvider userProvider,
    ValueNotifier<bool> isActiveSubscription,
    ValueNotifier<bool?> canMessage,
  ) {
    return GestureDetector(
      onTap: () async {
        if (messageCtr.text.trim().isEmpty) return;

        // If we already computed permission and it's false, show blocked UI
        if (canMessage.value == false) {
          showSimpleNotification(
            const Text(
              "This profile allows chats only with matched or liked profiles",
            ),
            background: Colors.orange,
            duration: const Duration(seconds: 3),
            position: NotificationPosition.top,
            slideDismissDirection: DismissDirection.down,
            leading: const Icon(Icons.info),
          );
          return;
        }

        // Fallback: if permission is still loading, compute synchronously
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        if (currentUserId == null) {
          showSimpleNotification(
            Text("Error: User not authenticated"),
            background: Colors.red,
            duration: Duration(seconds: 2),
          );
          return;
        }

        if (canMessage.value == null) {
          // compute quickly before sending to be safe
          final hasLiked = await hasUserLikedMyProfile(user.uid, currentUserId);
          final permission = user.messagePermission?.toLowerCase();
          final resolved =
              hasLiked || permission == null || permission == "all";
          if (!resolved) {
            showSimpleNotification(
              const Text(
                "This profile allows chats only with matched or liked profiles",
              ),
              background: Colors.orange,
              duration: const Duration(seconds: 3),
              position: NotificationPosition.top,
              slideDismissDirection: DismissDirection.down,
              leading: const Icon(Icons.info),
            );
            canMessage.value = false;
            return;
          }
          canMessage.value = true;
        }

        _handleSendMessage(context, chatRoom, user, messageCtr, userProvider);
      },
      child: Container(
        padding: EdgeInsets.all(getProportionateScreenWidth(12)),
        height: getProportionateScreenWidth(46),
        width: getProportionateScreenWidth(46),
        decoration: const BoxDecoration(
          color: kPrimaryColor,
          shape: BoxShape.circle,
        ),
        child: const Icon(Iconsax.send_21, color: Colors.white),
      ),
    );
  }

  /// Handles image upload logic - delegates to business logic and repository
  Future<void> _handleImageUpload(
    BuildContext context,
    ChatRoom chatRoom,
    UserDetails user,
    UserProvider userProvider,
    ValueNotifier<bool> isActiveSubscription,
  ) async {
    final hasSubscription = isActiveSubscription.value;
    final coins = userProvider.userDetails.coins ?? 0;
    final isFemale = userProvider.userDetails.gender?.toLowerCase() == 'female';

    if (((coins > 0 || coins == -1) && hasSubscription)) {
      ImageUploadService.sendMultipleImageMessage(
        context,
        chatRoom.roomId,
        user,
        coins,
        isFemale,
      );

      await MessageHelper.updateLastDateIfNeeded();
      return;
    }

    // From here onward: user has no coins

    // ❌ No coins + active subscription
    if (hasSubscription && coins == 0) {
      CustomDialog.outOfCoinsDialog(context);
      return;
    }

    // ❌ No coins + inactive subscription
    ReusableDialog.show(
      context,
      "Invalid subscription !",
      "Subscribe to access this feature.",
      "Subscribe",
      onConfirm: () async {
        await PersistentNavBarNavigator.pushNewScreen(
          context,
          screen: PaymentScreen(showArrowBack: true),
          withNavBar: false,
          pageTransitionAnimation: PageTransitionAnimation.cupertino,
        );
      },
    );
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

    if ((userProvider.userDetails.coins ?? 0) == 0) {
      FocusScope.of(context).unfocus();
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
    await MessageHelper.updateLastDateIfNeeded();
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
