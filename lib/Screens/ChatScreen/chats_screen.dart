import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/constants.dart';
import 'package:viora/models/ChatRoom.dart';
import 'package:viora/Services/exceptions/exceptions.dart';
import 'package:viora/Services/SubscriptionService.dart';
import 'package:viora/utils/helpers/message_helper.dart';
import '../../size_config.dart';
import 'components/chat_card.dart';

class ChatsScreen extends HookWidget {
  final bool hideAppBar;
  final bool isActiveTab;

  const ChatsScreen({
    super.key,
    this.hideAppBar = false,
    this.isActiveTab = false,
  });
  @override
  Widget build(BuildContext context) {
    final refreshKey = useState(GlobalKey<RefreshIndicatorState>());
    final authUser = FirebaseAuth.instance.currentUser;
    final wasActive = useRef(false);
    final hasActiveSubscription = useState<bool?>(null);

    void refresh() {
      refreshKey.value = GlobalKey<RefreshIndicatorState>();
    }

    Future<void> onEnterScreen() async {
      return await MessageHelper.updateLastDateIfNeeded();
    }

    final globals = Globals.of(context);

    // Listen to user details changes using hook
    final userDetails = useListenable(globals.prefs.userDetails);
    final currentUser = userDetails.value;

    useEffect(() {
      if (currentUser == null) {
        hasActiveSubscription.value = null;
        return null;
      }

      var cancelled = false;

      () async {
        final active = await SubscriptionService.isSubscriptionActive(
          currentUser.uid,
        );
        if (!cancelled) {
          hasActiveSubscription.value = active;
        }
      }();

      return () {
        cancelled = true;
      };
    }, [currentUser?.uid]);

    useEffect(() {
      if (!isActiveTab) {
        wasActive.value = false;
        return null;
      }

      if (wasActive.value || authUser == null || currentUser == null) {
        return null;
      }

      wasActive.value = true;
      onEnterScreen();
      return null;
    }, [isActiveTab, authUser?.uid, currentUser]);

    // During logout/reset there is a brief rebuild window where auth and prefs
    // can be null while this tab is still mounted in IndexedStack.
    if (authUser == null || currentUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF9F9), Color(0xFFF2ADC8)],
            stops: [0.3227, 1.5491],
          ),
        ),
        child: Stack(
          children: [
            // Background image
            Positioned.fill(
              child: Image.asset(
                'assets/backgrounds/interactions.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),

            // Main content column
            Column(
              children: [
                // --- HEADER SECTION ---
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(color: Color(0xFFFFF9F9)),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Background decorations
                      Positioned(
                        left: getProportionateScreenWidth(-97),
                        top: getProportionateScreenHeight(-90),
                        child: Transform(
                          transform: Matrix4.identity()..scale(-1.0, 1.0),
                          alignment: Alignment.center,
                          child: Image.asset(
                            "assets/icon/viora_transparent.png",
                            width: getProportionateScreenWidth(270),
                            height: getProportionateScreenHeight(210),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        right: getProportionateScreenWidth(-120),
                        top: getProportionateScreenHeight(-97),
                        child: Image.asset(
                          "assets/icon/viora_transparent.png",
                          width: getProportionateScreenWidth(360),
                          height: getProportionateScreenHeight(270),
                          fit: BoxFit.cover,
                        ),
                      ),

                      // Header content
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: getProportionateScreenWidth(
                            kDefaultPadding,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height: getProportionateScreenHeight(44)),
                            Text(
                              'Messages',
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: getProportionateScreenWidth(34),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: getProportionateScreenHeight(4)),
                            currentUser.gender?.toLowerCase() == "female" &&
                                    currentUser.coins == -1
                                ? SizedBox.shrink()
                                : Text(
                                    hasActiveSubscription.value == false &&
                                            currentUser.coins == 0
                                        ? 'Chatting Not Allowed'
                                        : 'Remaining Messages: ${currentUser.coins == -1 ? "Unlimited" : currentUser.coins ?? 0}',
                                    style: TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: getProportionateScreenWidth(16),
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF838383),
                                    ),
                                  ),

                            SizedBox(height: getProportionateScreenHeight(35)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // --- CONTENT SECTION ---
                Expanded(
                  child: RefreshIndicator(
                    key: refreshKey.value,
                    onRefresh: () async {
                      refresh();
                    },
                    child: FirestoreQueryBuilder<Map<String, dynamic>>(
                      query: FirebaseFirestore.instance
                          .collection('ChatRooms')
                          .orderBy('lastMessageDate', descending: true)
                          .where("users", arrayContains: authUser.uid),
                      pageSize: 20,
                      builder: (context, snapshot, _) {
                        if (snapshot.isFetching && snapshot.docs.isEmpty) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (snapshot.hasError) {
                          final error = snapshot.error;
                          final appException = ErrorHandler.convert(
                            error,
                            StackTrace.current,
                          );
                          return Center(
                            child: Padding(
                              padding: EdgeInsets.all(
                                getProportionateScreenWidth(24),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: getProportionateScreenWidth(60),
                                    color: Colors.red[300],
                                  ),
                                  SizedBox(
                                    height: getProportionateScreenHeight(16),
                                  ),
                                  Text(
                                    appException.userMessage,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: getProportionateScreenWidth(16),
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  SizedBox(
                                    height: getProportionateScreenHeight(16),
                                  ),
                                  ElevatedButton(
                                    onPressed: refresh,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        // --- FILTERING LOGIC ---
                        // 1. Filter out chats with empty lastMessage
                        final validChats = snapshot.docs.where((doc) {
                          final data = doc.data();
                          final lastMsg = data['lastMessage'] as String?;
                          return lastMsg != null && lastMsg.isNotEmpty;
                        }).toList();

                        // 2. Check if the *filtered* list is empty
                        if (validChats.isEmpty) {
                          return Center(
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: getProportionateScreenWidth(80),
                                    color: Colors.grey.withAlpha(102),
                                  ),
                                  SizedBox(
                                    height: getProportionateScreenHeight(16),
                                  ),
                                  Text(
                                    "No Messages Yet",
                                    style: TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: getProportionateScreenWidth(20),
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  SizedBox(
                                    height: getProportionateScreenHeight(8),
                                  ),
                                  Text(
                                    "Match with someone to start chatting!",
                                    style: TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: getProportionateScreenWidth(14),
                                      color: const Color(0xFF797979),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        // -----------------------

                        return ListView.builder(
                          // 3. Use the length of validChats
                          itemCount: validChats.length,
                          padding: EdgeInsets.only(
                            left: getProportionateScreenWidth(17),
                            right: getProportionateScreenWidth(17),
                            top: getProportionateScreenHeight(8),
                            bottom: getProportionateScreenHeight(8),
                          ),
                          itemBuilder: (context, index) {
                            // Trigger pagination if we reach the end
                            if (snapshot.hasMore &&
                                index + 1 == validChats.length) {
                              snapshot.fetchMore();
                            }

                            // 4. Use data from validChats
                            final data = validChats[index].data();
                            final chatRoom = ChatRoom.fromJson(data);
                            final isLast = index == validChats.length - 1;

                            return InteractionChatCard(
                              chatRoom: chatRoom,
                              isLast: isLast,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
