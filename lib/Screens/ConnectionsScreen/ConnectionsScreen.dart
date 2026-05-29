import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:viora/Screens/Home/homeScreen.dart';
import 'package:viora/Screens/MessagesScreen/new_message_screen.dart';
import 'package:viora/Screens/ProfileScreen/new_profile_view.dart';
import 'package:viora/components/verified_badge.dart';

// Make sure to import your own project files here
import 'package:viora/constants.dart';
import 'package:viora/size_config.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:viora/Services/AppConfigService.dart';
import 'package:viora/Services/ImageHelper.dart';
import 'package:viora/Services/exceptions/exceptions.dart';
import 'package:viora/utils/helpers/image_helper.dart';

// Helper for conditional logging
void _logConnection(String message) {
  if (kDebugMode) {
    debugPrint('[ConnectionsScreen] $message');
  }
}

// --- ENUMS ---
enum ConnectionType { all, matched, liked, viewed }

// --- CONNECTION ITEM MODEL ---
class ConnectionItem {
  final String uid;
  final DateTime date;
  final String type; // 'liked', 'viewed', 'match', 'youViewed'

  ConnectionItem({required this.uid, required this.date, required this.type});
}

// --- HELPER: SORT BY ACTIVE STATUS ---
// Sorts a list so that Online users appear first, then sorts by Date.
Future<List<ConnectionItem>> _sortConnectionsByActiveStatus(
  List<ConnectionItem> items,
) async {
  List<Map<String, dynamic>> sortableItems = [];

  // 1. Fetch user data in parallel to check 'isOnline' status
  await Future.wait(
    items.map((item) async {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(item.uid)
            .get();
        if (doc.exists) {
          final data = doc.data();
          final isOnline = data?['isOnline'] == true;
          sortableItems.add({'item': item, 'isOnline': isOnline});
        }
      } catch (e, stackTrace) {
        // Handle error or deleted user gently
        _logConnection('Error fetching user status: $e');
        final appException = ErrorHandler.convert(e, stackTrace);
        _logConnection('Converted to: ${appException.runtimeType}');
      }
    }),
  );

  // 2. Sort: Active users first (-1), then fallback to Date descending
  sortableItems.sort((a, b) {
    final bool aOnline = a['isOnline'];
    final bool bOnline = b['isOnline'];

    if (aOnline && !bOnline)
      return -1; // a is online, b is not -> a comes first
    if (!aOnline && bOnline) return 1; // b is online, a is not -> b comes first

    // If both have same status, sort by date (newest first)
    final DateTime aDate = (a['item'] as ConnectionItem).date;
    final DateTime bDate = (b['item'] as ConnectionItem).date;
    return bDate.compareTo(aDate);
  });

  // 3. Map back to ConnectionItem list
  return sortableItems.map((e) => e['item'] as ConnectionItem).toList();
}

// --- MAIN WIDGET ---
class ConnectionsScreen extends HookWidget {
  final bool hideAppBar;

  const ConnectionsScreen({super.key, this.hideAppBar = false});

  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFFFF9F9),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final userId = authUser.uid;
    final tabIndex = useState(0);
    final tabs = ["Feed", "Matched", "Liked", "Viewed"];

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9F9),
      body: Column(
        children: [
          // Custom Header
          _buildCustomHeader(context, tabs, tabIndex),

          // Content Grid
          Expanded(child: _buildTabContent(context, tabIndex.value, userId)),
        ],
      ),
    );
  }

  Widget _buildCustomHeader(
    BuildContext context,
    List<String> tabs,
    ValueNotifier<int> tabIndex,
  ) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(color: Color(0xFFFFF9F9)),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // --- Background Decor ---
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

          // --- Main Content ---
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: getProportionateScreenWidth(kDefaultPadding),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: getProportionateScreenHeight(44)),
                // Title
                Text(
                  'Connections',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: getProportionateScreenWidth(34),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: getProportionateScreenHeight(5)),

                // Subtitle
                Text(
                  'This is a list of people who have either viewed, liked or are a match with you.',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: getProportionateScreenWidth(16),
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF838383),
                    height: 1.4,
                  ),
                ),

                SizedBox(height: getProportionateScreenHeight(25)),

                // --- TABS ROW ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(tabs.length, (index) {
                    final isSelected = tabIndex.value == index;
                    return GestureDetector(
                      onTap: () => tabIndex.value = index,
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tabs[index],
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: getProportionateScreenWidth(18),
                              fontWeight: FontWeight.w700,
                              color: isSelected ? kTertiaryPink : Colors.black,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),

                SizedBox(height: getProportionateScreenHeight(15)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(BuildContext context, int tabIndex, String userId) {
    switch (tabIndex) {
      case 0: // All (Standard Date Sort)
        return _AllConnectionsView(userId: userId);
      case 1: // Matched (Sorted by Active)
        return _MatchedConnectionsView(userId: userId);
      case 2: // Liked (Sorted by Active)
        return _LikedConnectionsView(userId: userId);
      case 3: // Viewed (Infinite Scroll + Batch Active Sort)
        return _ViewedConnectionsView(userId: userId);
      default:
        return const SizedBox();
    }
  }
}

// --- ALL CONNECTIONS VIEW (No Active Sort, Pure Date) ---
class _AllConnectionsView extends HookWidget {
  final String userId;

  const _AllConnectionsView({required this.userId});

  @override
  Widget build(BuildContext context) {
    final connections = useState<List<ConnectionItem>>([]);
    final isLoading = useState(true);
    final refreshKey = useState(0);

    useEffect(() {
      _loadAllConnections(userId, connections, isLoading);
      return null;
    }, [refreshKey.value]);

    if (isLoading.value) {
      return const Center(child: CircularProgressIndicator());
    }

    if (connections.value.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              AppConfigService.allTabEmptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                AppConfigService.allTabEmptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => refreshKey.value++,
      child: GridView.builder(
        key: const PageStorageKey('all_user_list'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 6,
          childAspectRatio: 177 / 195,
        ),
        itemCount: connections.value.length,
        itemBuilder: (context, index) {
          final item = connections.value[index];
          return _ConnectionUserCard(
            uid: item.uid,
            connectionType: item.type,
            showBadge: true,
          );
        },
      ),
    );
  }

  Future<void> _loadAllConnections(
    String userId,
    ValueNotifier<List<ConnectionItem>> connections,
    ValueNotifier<bool> isLoading,
  ) async {
    try {
      final List<ConnectionItem> allConnections = [];
      final Set<String> addedUids = {};
      final Set<String> matchedUids = {};

      final crushOnMeSnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .collection('CrushOnMe')
          .orderBy('date', descending: true)
          .limit(50)
          .get();
      final myCrushSnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .collection('MyCrush')
          .orderBy('date', descending: true)
          .limit(50)
          .get();

      final myCrushUids = myCrushSnapshot.docs
          .map((doc) => doc.data()['uid'] as String?)
          .whereType<String>()
          .toSet();

      final enabledCrushOnMe = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in crushOnMeSnapshot.docs) {
        final uid = doc.data()['uid'] as String?;
        if (uid != null) {
          final userDoc = await FirebaseFirestore.instance
              .collection('Users')
              .doc(uid)
              .get();
          if (userDoc.exists && (userDoc.data()?['isDisabled'] != true)) {
            enabledCrushOnMe.add(doc);
          }
        }
      }

      for (final doc in enabledCrushOnMe) {
        final data = doc.data();
        if (data == null) continue;
        final uid = data['uid'] as String?;
        final date = data['date'] as Timestamp?;
        if (uid != null && date != null && !addedUids.contains(uid)) {
          addedUids.add(uid);
          final isMatch = myCrushUids.contains(uid);
          if (isMatch) matchedUids.add(uid);
          allConnections.add(
            ConnectionItem(
              uid: uid,
              date: date.toDate(),
              type: isMatch ? 'match' : 'crush',
            ),
          );
        }
      }

      final favOnMeSnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .collection('FavOnMe')
          .orderBy('date', descending: true)
          .limit(50)
          .get();
      for (final doc in favOnMeSnapshot.docs) {
        final data = doc.data();
        final uid = data['uid'] as String?;
        if (uid != null &&
            !addedUids.contains(uid) &&
            !matchedUids.contains(uid)) {
          final userDoc = await FirebaseFirestore.instance
              .collection('Users')
              .doc(uid)
              .get();
          if (userDoc.exists && (userDoc.data()?['isDisabled'] != true)) {
            addedUids.add(uid);
            allConnections.add(
              ConnectionItem(
                uid: uid,
                date: (data['date'] as Timestamp).toDate(),
                type: 'liked',
              ),
            );
          }
        }
      }

      for (final doc in myCrushSnapshot.docs) {
        final data = doc.data();
        final uid = data['uid'] as String?;
        if (uid != null &&
            !addedUids.contains(uid) &&
            !matchedUids.contains(uid)) {
          final userDoc = await FirebaseFirestore.instance
              .collection('Users')
              .doc(uid)
              .get();
          if (userDoc.exists && (userDoc.data()?['isDisabled'] != true)) {
            addedUids.add(uid);
            allConnections.add(
              ConnectionItem(
                uid: uid,
                date: (data['date'] as Timestamp).toDate(),
                type: 'yourCrush',
              ),
            );
          }
        }
      }

      final viewNotificationsSnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .collection('Notifications')
          .where('type', isEqualTo: 'View')
          .orderBy('date', descending: true)
          .limit(50)
          .get();
      for (final doc in viewNotificationsSnapshot.docs) {
        final data = doc.data();
        final uid = data['uid'] as String?;
        if (uid != null && !addedUids.contains(uid)) {
          final userDoc = await FirebaseFirestore.instance
              .collection('Users')
              .doc(uid)
              .get();
          if (userDoc.exists && (userDoc.data()?['isDisabled'] != true)) {
            addedUids.add(uid);
            allConnections.add(
              ConnectionItem(
                uid: uid,
                date: (data['date'] as Timestamp).toDate(),
                type: 'viewed',
              ),
            );
          }
        }
      }

      allConnections.sort((a, b) => b.date.compareTo(a.date));
      try {
        connections.value = allConnections;
        isLoading.value = false;
      } catch (e) {
        // Widget was disposed, ignore
      }
    } catch (e, stackTrace) {
      _logConnection('Error loading connections: $e');
      final appException = ErrorHandler.convert(e, stackTrace);
      _logConnection('Converted to: ${appException.runtimeType}');
      try {
        isLoading.value = false;
      } catch (e) {
        // Widget was disposed, ignore
      }
    }
  }
}

// --- MATCHED CONNECTIONS VIEW (Sorted by Active) ---
class _MatchedConnectionsView extends HookWidget {
  final String userId;

  const _MatchedConnectionsView({required this.userId});

  @override
  Widget build(BuildContext context) {
    final matches = useState<List<ConnectionItem>>([]);
    final isLoading = useState(true);
    final refreshKey = useState(0);

    useEffect(() {
      _loadMatches(userId, matches, isLoading);
      return null;
    }, [refreshKey.value]);

    if (isLoading.value) {
      return const Center(child: CircularProgressIndicator());
    }

    if (matches.value.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No matches yet',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'When you and someone both have a crush\non each other, they\'ll appear here',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => refreshKey.value++,
      child: GridView.builder(
        key: const PageStorageKey('matched_user_list'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 177 / 195,
        ),
        itemCount: matches.value.length,
        itemBuilder: (context, index) {
          final item = matches.value[index];
          return _ConnectionUserCard(
            uid: item.uid,
            connectionType: 'match',
            showBadge: false,
          );
        },
      ),
    );
  }

  Future<void> _loadMatches(
    String userId,
    ValueNotifier<List<ConnectionItem>> matches,
    ValueNotifier<bool> isLoading,
  ) async {
    try {
      final List<ConnectionItem> matchList = [];

      final crushOnMeSnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .collection('CrushOnMe')
          .get();
      final myCrushSnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .collection('MyCrush')
          .get();

      final myCrushUids = myCrushSnapshot.docs
          .map((doc) => doc.data()['uid'] as String?)
          .whereType<String>()
          .toSet();

      for (final doc in crushOnMeSnapshot.docs) {
        final data = doc.data();
        final uid = data['uid'] as String?;
        final date = data['date'] as Timestamp?;
        if (uid != null && date != null && myCrushUids.contains(uid)) {
          matchList.add(
            ConnectionItem(uid: uid, date: date.toDate(), type: 'match'),
          );
        }
      }

      // Sort: Active Users First
      final sortedMatches = await _sortConnectionsByActiveStatus(matchList);

      try {
        matches.value = sortedMatches;
        isLoading.value = false;
      } catch (e) {
        // Widget was disposed, ignore
      }
    } catch (e, stackTrace) {
      _logConnection('Error loading matches: $e');
      final appException = ErrorHandler.convert(e, stackTrace);
      _logConnection('Converted to: ${appException.runtimeType}');
      try {
        isLoading.value = false;
      } catch (e) {
        // Widget was disposed, ignore
      }
    }
  }
}

// --- LIKED CONNECTIONS VIEW (Sorted by Active) ---
class _LikedConnectionsView extends HookWidget {
  final String userId;

  const _LikedConnectionsView({required this.userId});

  @override
  Widget build(BuildContext context) {
    final liked = useState<List<ConnectionItem>>([]);
    final isLoading = useState(true);
    final refreshKey = useState(0);

    useEffect(() {
      _loadLiked(userId, liked, isLoading);
      return null;
    }, [refreshKey.value]);

    if (isLoading.value) {
      return const Center(child: CircularProgressIndicator());
    }

    if (liked.value.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No one has liked you yet',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => refreshKey.value++,
      child: GridView.builder(
        key: const PageStorageKey('liked_user_list'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 177 / 195,
        ),
        itemCount: liked.value.length,
        itemBuilder: (context, index) {
          final item = liked.value[index];
          return _ConnectionUserCard(
            uid: item.uid,
            connectionType: 'liked',
            showBadge: false,
          );
        },
      ),
    );
  }

  Future<void> _loadLiked(
    String userId,
    ValueNotifier<List<ConnectionItem>> liked,
    ValueNotifier<bool> isLoading,
  ) async {
    try {
      final List<ConnectionItem> likedList = [];
      final Set<String> addedUids = {};

      final myCrushSnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .collection('MyCrush')
          .get();
      final myCrushUids = myCrushSnapshot.docs
          .map((doc) => doc.data()['uid'] as String?)
          .whereType<String>()
          .toSet();

      final crushOnMeSnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .collection('CrushOnMe')
          .orderBy('date', descending: true)
          .get();

      for (final doc in crushOnMeSnapshot.docs) {
        final data = doc.data();
        final uid = data['uid'] as String?;
        if (uid != null &&
            !addedUids.contains(uid) &&
            !myCrushUids.contains(uid)) {
          final userDoc = await FirebaseFirestore.instance
              .collection('Users')
              .doc(uid)
              .get();
          if (userDoc.exists && (userDoc.data()?['isDisabled'] != true)) {
            addedUids.add(uid);
            likedList.add(
              ConnectionItem(
                uid: uid,
                date: (data['date'] as Timestamp).toDate(),
                type: 'liked',
              ),
            );
          }
        }
      }

      final favOnMeSnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .collection('FavOnMe')
          .orderBy('date', descending: true)
          .get();

      for (final doc in favOnMeSnapshot.docs) {
        final data = doc.data();
        final uid = data['uid'] as String?;
        if (uid != null &&
            !addedUids.contains(uid) &&
            !myCrushUids.contains(uid)) {
          final userDoc = await FirebaseFirestore.instance
              .collection('Users')
              .doc(uid)
              .get();
          if (userDoc.exists && (userDoc.data()?['isDisabled'] != true)) {
            addedUids.add(uid);
            likedList.add(
              ConnectionItem(
                uid: uid,
                date: (data['date'] as Timestamp).toDate(),
                type: 'liked',
              ),
            );
          }
        }
      }

      // Sort: Active Users First
      final sortedLiked = await _sortConnectionsByActiveStatus(likedList);

      try {
        liked.value = sortedLiked;
        isLoading.value = false;
      } catch (e) {
        // Widget was disposed, ignore
      }
    } catch (e, stackTrace) {
      _logConnection('Error loading liked: $e');
      final appException = ErrorHandler.convert(e, stackTrace);
      _logConnection('Converted to: ${appException.runtimeType}');
      try {
        isLoading.value = false;
      } catch (e) {
        // Widget was disposed, ignore
      }
    }
  }
}

// --- VIEWED CONNECTIONS VIEW (Infinite Scroll + Batch Active Sort) ---
class _ViewedConnectionsView extends HookWidget {
  final String userId;

  const _ViewedConnectionsView({required this.userId});

  @override
  Widget build(BuildContext context) {
    // State management for infinite scroll
    final viewed = useState<List<ConnectionItem>>([]);
    final isLoading = useState(true);
    final isLoadingMore = useState(false);
    final lastDoc = useState<DocumentSnapshot?>(null);
    final hasMore = useState(true);

    // Scroll Controller
    final scrollController = useScrollController();

    // Initial Load
    useEffect(() {
      _loadNextBatch(
        userId,
        viewed,
        isLoading,
        isLoadingMore,
        lastDoc,
        hasMore,
        isInitial: true,
      );
      return null;
    }, []);

    // Scroll Listener
    useEffect(() {
      void onScroll() {
        if (!scrollController.hasClients) return;
        final maxScroll = scrollController.position.maxScrollExtent;
        final currentScroll = scrollController.offset;

        // Trigger load when close to bottom
        if (currentScroll >= (maxScroll - 200) &&
            !isLoadingMore.value &&
            hasMore.value) {
          _loadNextBatch(
            userId,
            viewed,
            isLoading,
            isLoadingMore,
            lastDoc,
            hasMore,
          );
        }
      }

      scrollController.addListener(onScroll);
      return () => scrollController.removeListener(onScroll);
    }, [scrollController]);

    if (isLoading.value) {
      return const Center(child: CircularProgressIndicator());
    }

    if (viewed.value.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.visibility_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No one has viewed your profile yet',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        viewed.value = [];
        lastDoc.value = null;
        hasMore.value = true;
        await _loadNextBatch(
          userId,
          viewed,
          isLoading,
          isLoadingMore,
          lastDoc,
          hasMore,
          isInitial: true,
        );
      },
      child: GridView.builder(
        key: const PageStorageKey('viewed_user_list'),
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 177 / 195,
        ),
        // Add spinner item if loading more
        itemCount: viewed.value.length + (isLoadingMore.value ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == viewed.value.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final item = viewed.value[index];
          return _ConnectionUserCard(
            uid: item.uid,
            connectionType: 'viewed',
            showBadge: false,
          );
        },
      ),
    );
  }

  Future<void> _loadNextBatch(
    String userId,
    ValueNotifier<List<ConnectionItem>> viewed,
    ValueNotifier<bool> isLoading,
    ValueNotifier<bool> isLoadingMore,
    ValueNotifier<DocumentSnapshot?> lastDoc,
    ValueNotifier<bool> hasMore, {
    bool isInitial = false,
  }) async {
    if (isInitial)
      isLoading.value = true;
    else
      isLoadingMore.value = true;

    try {
      // Exclude from Viewed: people who liked you (FavOnMe/CrushOnMe), matches (MyCrush),
      // and people YOU liked/favorited (MyFav) — they belong in Liked/Matched, not Viewed.
      final excludeFromViewedFuture = Future(() async {
        final results = await Future.wait([
          FirebaseFirestore.instance
              .collection('Users')
              .doc(userId)
              .collection('FavOnMe')
              .get(),
          FirebaseFirestore.instance
              .collection('Users')
              .doc(userId)
              .collection('CrushOnMe')
              .get(),
          FirebaseFirestore.instance
              .collection('Users')
              .doc(userId)
              .collection('MyCrush')
              .get(),
          FirebaseFirestore.instance
              .collection('Users')
              .doc(userId)
              .collection('MyFav')
              .get(),
        ]);
        final exclude = <String>{};
        for (final snapshot in results) {
          for (final doc in snapshot.docs) {
            final uid = doc.data()['uid'] as String?;
            if (uid != null) exclude.add(uid);
          }
        }
        return exclude;
      });

      final int batchSize = 20;
      Query query = FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .collection('Notifications')
          .where('type', isEqualTo: 'View')
          .orderBy('date', descending: true)
          .limit(batchSize);

      if (lastDoc.value != null) {
        query = query.startAfterDocument(lastDoc.value!);
      }

      final snapshot = await query.get();
      final excludeFromViewed = await excludeFromViewedFuture;

      if (snapshot.docs.isEmpty) {
        try {
          hasMore.value = false;
          isLoading.value = false;
          isLoadingMore.value = false;
        } catch (e) {
          // Widget was disposed, ignore
        }
        return;
      }

      lastDoc.value = snapshot.docs.last;

      if (snapshot.docs.length < batchSize) {
        try {
          hasMore.value = false;
        } catch (e) {
          // Widget was disposed, ignore
        }
      }

      final List<ConnectionItem> newBatch = [];
      final Set<String> existingUids = viewed.value.map((e) => e.uid).toSet();

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final uid = data['uid'] as String?;

        // Exclude: already in list, or in Liked/Matched (show only in those tabs)
        if (uid != null &&
            !existingUids.contains(uid) &&
            !excludeFromViewed.contains(uid)) {
          newBatch.add(
            ConnectionItem(
              uid: uid,
              date: (data['date'] as Timestamp).toDate(),
              type: 'viewed',
            ),
          );
        }
      }

      // Sort ONLY this batch by Active status
      final sortedBatch = await _sortConnectionsByActiveStatus(newBatch);

      try {
        if (isInitial) {
          viewed.value = sortedBatch;
        } else {
          viewed.value = [...viewed.value, ...sortedBatch];
        }
      } catch (e) {
        // Widget was disposed, ignore
      }
    } catch (e, stackTrace) {
      _logConnection('Error loading viewed batch: $e');
      final appException = ErrorHandler.convert(e, stackTrace);
      _logConnection('Converted to: ${appException.runtimeType}');
    } finally {
      try {
        isLoading.value = false;
        isLoadingMore.value = false;
      } catch (e) {
        // Widget was disposed, ignore
      }
    }
  }
}

// --- CONNECTION USER CARD (UI FIXED) ---
class _ConnectionUserCard extends StatefulWidget {
  final String uid;
  final String connectionType;
  final bool showBadge;

  const _ConnectionUserCard({
    required this.uid,
    required this.connectionType,
    required this.showBadge,
  });

  @override
  State<_ConnectionUserCard> createState() => _ConnectionUserCardState();
}

class _ConnectionUserCardState extends State<_ConnectionUserCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  UserDetails? user;
  bool isLoading = true;
  bool userDeleted = false; // Track if user document doesn't exist
  String? backgroundImageUrl;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      // Use GetOptions.source to bypass cache and get fresh data from server
      // This ensures we don't show deleted users from cached data
      final doc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(widget.uid)
          .get(const GetOptions(source: Source.serverAndCache));

      if (!doc.exists) {
        // User document doesn't exist (deleted account)
        _logConnection('User ${widget.uid} not found - likely deleted');
        if (mounted) {
          setState(() {
            userDeleted = true;
            isLoading = false;
          });
        }
        return;
      }

      if (mounted) {
        final userData = UserDetails.fromJson(doc.data()!);

        // Check if user is disabled
        if (userData.isDisabled == true) {
          setState(() {
            userDeleted = true;
            isLoading = false;
          });
          return;
        }

        // Get consistent background image if user has no profile images
        String? bgImage;
        if (userData.images?.isEmpty ?? true) {
          bgImage = ImageHelper.getConsistentBackgroundForUser(widget.uid);
        }

        setState(() {
          user = userData;
          backgroundImageUrl = bgImage;
          isLoading = false;
        });
      }
    } catch (e) {
      _logConnection('Error loading user ${widget.uid}: $e');
      if (mounted) {
        setState(() {
          userDeleted = true; // Treat errors as deleted user
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (isLoading) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    // Hide card if user is deleted, disabled, or not found
    if (userDeleted || user == null || user!.isDisabled == true) {
      return const SizedBox.shrink();
    }

    final imageUrl = (user!.images?.isNotEmpty ?? false)
        ? user!.images![0]
        : AppConfigService.getPlaceholderImageUrl(user!.gender);

    return GestureDetector(
      onTap: () {
        showViewProfileScreen.value = user?.uid ?? '';
        // PersistentNavBarNavigator.pushNewScreen(
        //   context,
        //   screen: NewProfileView(uid: user!.uid),
        //   withNavBar: false,
        //   pageTransitionAnimation: PageTransitionAnimation.cupertino,
        // );
      },
      child: SizedBox(
        width: getProportionateScreenWidth(177),
        height: getProportionateScreenHeight(212),
        child: Stack(
          children: [
            // Background Image (if user has no profile image)
            if (backgroundImageUrl != null)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CachedNetworkImage(
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    imageUrl: backgroundImageUrl!,
                    placeholder: (context, url) =>
                        Container(color: Colors.grey[200]),
                    errorWidget: (context, url, error) =>
                        Container(color: Colors.grey[200]),
                  ),
                ),
              ),

            // Foreground Image (Profile or Placeholder)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ReactiveProfileImage(
                  imagePath: imageUrl,
                  gender: user?.gender ?? "male",
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
            // Active Badge (Top Left)
            if (user!.isOnline == true)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFBFFFBF),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    'Active',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF16AC16),
                      height: 15 / 11,
                    ),
                  ),
                ),
              ),

            if (user!.isVerified == true)
              Positioned(
                right: 6,
                top: 6,
                child: VerifiedBadge(),
                // child: ReactiveBadgeImage(
                //   badgePath: AppConfigService.verifiedBadgeUri,
                //   width: 22,
                //   height: 22,
                // ),
              ),

            // Connection Type Badge
            if (widget.showBadge)
              Positioned(left: 0, bottom: 52, child: _buildConnectionBadge()),

            // Bottom Info Container (UI FIX APPLIED HERE)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 53,
                // Define the shape
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  ),
                ),
                // Force clip of content (including blur) to shape
                clipBehavior: Clip.hardEdge,
                child: Stack(
                  children: [
                    // Layer 1: Blur
                    Positioned.fill(
                      child: BackdropFilter(
                        // Strict Match to CSS: 10.05px blur
                        filter: ImageFilter.blur(sigmaX: 10.05, sigmaY: 10.05),
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                    // Layer 2: Content + Color Overlay
                    Container(
                      decoration: BoxDecoration(
                        // Strict Match to CSS: 0.18 opacity
                        color: const Color(0xFF3E1E68).withOpacity(0.18),
                        border: const Border(
                          top: BorderSide(
                            color: Color(0x80FEFEFE), // ~50% white
                            width: 0.8,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Name and Location
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${user!.name}, ${user!.age}',
                                    style: const TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      height: 19 / 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  Text(
                                    '${user!.city}, ${user!.state}',
                                    style: const TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFFDFDFDF),
                                      height: 16 / 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ],
                              ),
                            ),
                            // Chat Icon
                            GestureDetector(
                              onTap: () async {
                                final currentUserId =
                                    FirebaseAuth.instance.currentUser?.uid;
                                if (currentUserId == null) {
                                  showSimpleNotification(
                                    Text("Error: User not authenticated"),
                                    background: Colors.red,
                                    duration: Duration(seconds: 2),
                                  );
                                  return;
                                }

                                final hasLiked = await hasUserLikedMyProfile(
                                  user?.uid ?? '',
                                  currentUserId,
                                );
                                final permission = user?.messagePermission
                                    ?.toLowerCase();

                                final canMessage =
                                    hasLiked ||
                                    permission == null ||
                                    permission == "all";

                                if (!canMessage) {
                                  showSimpleNotification(
                                    const Text(
                                      "This profile allows chats only with matched or liked profiles",
                                    ),
                                    background: Colors.orange,
                                    duration: const Duration(seconds: 3),
                                    position: NotificationPosition.top,
                                    slideDismissDirection:
                                        DismissDirection.down,
                                    leading: const Icon(Icons.info),
                                  );
                                  return;
                                }
                                PersistentNavBarNavigator.pushNewScreen(
                                  context,
                                  screen: NewMessagesScreen(uId: user!.uid),
                                  withNavBar: false,
                                  pageTransitionAnimation:
                                      PageTransitionAnimation.cupertino,
                                );
                              },
                              child: SvgPicture.asset(
                                'assets/svg/user_chat.svg',
                                colorFilter: const ColorFilter.mode(
                                  Colors.white,
                                  BlendMode.srcIn,
                                ),
                                width: 19.18,
                                height: 17.95,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionBadge() {
    String label;
    Color backgroundColor;
    Color textColor;
    // IconData? icon;
    String? svg;

    switch (widget.connectionType) {
      case 'match':
        label = 'Match';
        backgroundColor = const Color(0xFFFFD4DD);
        textColor = const Color(0xFFDC143C);
        // icon = Icons.favorite;
        svg = 'assets/svg/matched.svg';
        break;
      case 'crush':
      case 'liked':
        label = 'Liked';
        backgroundColor = const Color(0xFFFFE5F0).withAlpha(160);
        textColor = const Color(0xFFE45A92);
        // icon = Icons.favorite;
        svg = 'assets/svg/matched.svg';
        break;
      case 'viewed':
        label = 'Viewed';
        backgroundColor = const Color(0xFFC3DFFF).withAlpha(160);
        textColor = const Color(0xFF294E9D);
        // icon = Icons.visibility;
        svg = 'assets/svg/viewed.svg';
        break;
      case 'yourCrush':
        label = 'You Liked';
        backgroundColor = const Color(0xFFFFE5F0).withAlpha(160);
        textColor = const Color(0xFFE45A92);
        // icon = Icons.favorite;
        svg = 'assets/svg/crush_new.svg';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      height: 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
              height: 15 / 11,
            ),
          ),
          const SizedBox(width: 4),
          SvgPicture.asset(svg, width: 20, height: 20),
          // else
          //   Icon(icon, size: 16, color: textColor),
        ],
      ),
    );
  }
}
