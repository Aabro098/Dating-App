import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'DatabaseService.dart';

class ConnectionCountService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static bool _isPermissionDeniedError(Object error) {
    return error is FirebaseException && error.code == 'permission-denied';
  }

  static Future<int> getAllConnectionsCount(String userId) async {
    final Set<String> addedUids = {};

    final myCrushSnapshot = await _firestore
        .collection('Users')
        .doc(userId)
        .collection('MyCrush')
        .orderBy('date', descending: true)
        .limit(50)
        .get();

    for (final doc in myCrushSnapshot.docs) {
      final uid = doc.data()['uid'] as String?;
      if (uid == null) continue;

      final userDoc = await _firestore.collection('Users').doc(uid).get();

      if (userDoc.exists && userDoc.data()?['isDisabled'] != true) {
        addedUids.add(uid);
      }
    }

    final myFavSnapshot = await _firestore
        .collection('Users')
        .doc(userId)
        .collection('MyFav')
        .orderBy('date', descending: true)
        .limit(50)
        .get();

    for (final doc in myFavSnapshot.docs) {
      final uid = doc.data()['uid'] as String?;
      if (uid == null) continue;

      final userDoc = await _firestore.collection('Users').doc(uid).get();

      if (userDoc.exists && userDoc.data()?['isDisabled'] != true) {
        addedUids.add(uid);
      }
    }

    final crushOnMeSnapshot = await _firestore
        .collection('Users')
        .doc(userId)
        .collection('CrushOnMe')
        .orderBy('date', descending: true)
        .limit(50)
        .get();

    for (final doc in crushOnMeSnapshot.docs) {
      final uid = doc.data()['uid'] as String?;
      if (uid == null) continue;
      if (doc.data()['seen'] == true) continue;

      final userDoc = await _firestore.collection('Users').doc(uid).get();

      if (userDoc.exists && userDoc.data()?['isDisabled'] != true) {
        addedUids.add(uid);
      }
    }

    final favOnMeSnapshot = await _firestore
        .collection('Users')
        .doc(userId)
        .collection('FavOnMe')
        .orderBy('date', descending: true)
        .limit(50)
        .get();

    for (final doc in favOnMeSnapshot.docs) {
      final uid = doc.data()['uid'] as String?;
      if (uid == null) continue;
      if (doc.data()['seen'] == true) continue;

      if (!addedUids.contains(uid)) {
        final userDoc = await _firestore.collection('Users').doc(uid).get();

        if (userDoc.exists && userDoc.data()?['isDisabled'] != true) {
          addedUids.add(uid);
        }
      }
    }

    final viewNotificationsSnapshot = await _firestore
        .collection('Users')
        .doc(userId)
        .collection('Notifications')
        .where('type', isEqualTo: 'View')
        .orderBy('date', descending: true)
        .limit(50)
        .get();

    for (final doc in viewNotificationsSnapshot.docs) {
      final uid = doc.data()['uid'] as String?;
      if (uid == null) continue;
      if (doc.data()['seen'] == true) continue;

      if (!addedUids.contains(uid)) {
        final userDoc = await _firestore.collection('Users').doc(uid).get();

        if (userDoc.exists && userDoc.data()?['isDisabled'] != true) {
          addedUids.add(uid);
        }
      }
    }

    return addedUids.length;
  }

  /// Get count of UNSEEN connections only
  /// Used for nav bar badge to show unseen notifications
  /// Counts: unseen crushes + unseen favs + unseen views (avoiding duplicates)
  static Future<int> getUnseenConnectionsCount(String userId) async {
    final Set<String> unseenUids = {};

    // Get unseen CrushOnMe (highest priority)
    final crushOnMeSnapshot = await _firestore
        .collection('Users')
        .doc(userId)
        .collection('CrushOnMe')
        .where('seen', isEqualTo: false)
        .orderBy('date', descending: true)
        .limit(50)
        .get();

    for (final doc in crushOnMeSnapshot.docs) {
      final uid = doc.data()['uid'] as String?;
      if (uid == null) continue;

      final userDoc = await _firestore.collection('Users').doc(uid).get();

      if (userDoc.exists && userDoc.data()?['isDisabled'] != true) {
        unseenUids.add(uid);
      }
    }

    // Get unseen FavOnMe (second priority)
    final favOnMeSnapshot = await _firestore
        .collection('Users')
        .doc(userId)
        .collection('FavOnMe')
        .where('seen', isEqualTo: false)
        .orderBy('date', descending: true)
        .limit(50)
        .get();

    for (final doc in favOnMeSnapshot.docs) {
      final uid = doc.data()['uid'] as String?;
      if (uid == null) continue;

      // Skip if already added from crush
      if (!unseenUids.contains(uid)) {
        final userDoc = await _firestore.collection('Users').doc(uid).get();

        if (userDoc.exists && userDoc.data()?['isDisabled'] != true) {
          unseenUids.add(uid);
        }
      }
    }

    // Get unseen View notifications (lowest priority - only if not in crush/fav)
    final viewNotificationsSnapshot = await _firestore
        .collection('Users')
        .doc(userId)
        .collection('Notifications')
        .where('type', isEqualTo: 'View')
        .where('seen', isEqualTo: false)
        .orderBy('date', descending: true)
        .limit(50)
        .get();

    for (final doc in viewNotificationsSnapshot.docs) {
      final uid = doc.data()['uid'] as String?;
      if (uid == null) continue;

      // Skip if already added from crush or fav
      if (!unseenUids.contains(uid)) {
        final userDoc = await _firestore.collection('Users').doc(uid).get();

        if (userDoc.exists && userDoc.data()?['isDisabled'] != true) {
          unseenUids.add(uid);
        }
      }
    }

    return unseenUids.length;
  }

  /// Stream for unseen connections count (for nav bar badge)
  static Stream<int> watchUnseenConnectionsCount(String userId) {
    final controller = StreamController<int>.broadcast();

    Future<void> emitCount() async {
      try {
        final count = await getUnseenConnectionsCount(userId);
        if (!controller.isClosed) {
          controller.add(count);
        }
      } catch (e) {
        if (_isPermissionDeniedError(e)) {
          if (!controller.isClosed) controller.add(0);
          return;
        }
        if (!controller.isClosed) {
          controller.addError(e);
        }
      }
    }

    final subscriptions = <StreamSubscription>[
      _firestore
          .collection('Users')
          .doc(userId)
          .collection('CrushOnMe')
          .where('seen', isEqualTo: false)
          .snapshots()
          .listen(
            (_) => emitCount(),
            onError: (error) {
              if (_isPermissionDeniedError(error)) {
                if (!controller.isClosed) controller.add(0);
                return;
              }
              if (!controller.isClosed) controller.addError(error);
            },
          ),

      _firestore
          .collection('Users')
          .doc(userId)
          .collection('FavOnMe')
          .where('seen', isEqualTo: false)
          .snapshots()
          .listen(
            (_) => emitCount(),
            onError: (error) {
              if (_isPermissionDeniedError(error)) {
                if (!controller.isClosed) controller.add(0);
                return;
              }
              if (!controller.isClosed) controller.addError(error);
            },
          ),

      _firestore
          .collection('Users')
          .doc(userId)
          .collection('Notifications')
          .where('type', isEqualTo: 'View')
          .where('seen', isEqualTo: false)
          .snapshots()
          .listen(
            (_) => emitCount(),
            onError: (error) {
              if (_isPermissionDeniedError(error)) {
                if (!controller.isClosed) controller.add(0);
                return;
              }
              if (!controller.isClosed) controller.addError(error);
            },
          ),
    ];

    emitCount();

    controller.onCancel = () async {
      for (final sub in subscriptions) {
        await sub.cancel();
      }
    };

    return controller.stream;
  }

  static Stream<int> watchAllConnectionsCount(String userId) {
    final controller = StreamController<int>.broadcast();

    Future<void> emitCount() async {
      try {
        final count = await getAllConnectionsCount(userId);
        DatabaseService.updateUserField(userId, {'connectionCount': count});
        if (!controller.isClosed) {
          controller.add(count);
        }
      } catch (e) {
        if (_isPermissionDeniedError(e)) {
          if (!controller.isClosed) controller.add(0);
          return;
        }
        if (!controller.isClosed) {
          controller.addError(e);
        }
      }
    }

    final subscriptions = <StreamSubscription>[
      _firestore
          .collection('Users')
          .doc(userId)
          .collection('MyCrush')
          .snapshots()
          .listen(
            (_) => emitCount(),
            onError: (error) {
              if (_isPermissionDeniedError(error)) {
                if (!controller.isClosed) controller.add(0);
                return;
              }
              if (!controller.isClosed) controller.addError(error);
            },
          ),

      _firestore
          .collection('Users')
          .doc(userId)
          .collection('MyFav')
          .snapshots()
          .listen(
            (_) => emitCount(),
            onError: (error) {
              if (_isPermissionDeniedError(error)) {
                if (!controller.isClosed) controller.add(0);
                return;
              }
              if (!controller.isClosed) controller.addError(error);
            },
          ),

      _firestore
          .collection('Users')
          .doc(userId)
          .collection('CrushOnMe')
          .snapshots()
          .listen(
            (_) => emitCount(),
            onError: (error) {
              if (_isPermissionDeniedError(error)) {
                if (!controller.isClosed) controller.add(0);
                return;
              }
              if (!controller.isClosed) controller.addError(error);
            },
          ),

      _firestore
          .collection('Users')
          .doc(userId)
          .collection('FavOnMe')
          .snapshots()
          .listen(
            (_) => emitCount(),
            onError: (error) {
              if (_isPermissionDeniedError(error)) {
                if (!controller.isClosed) controller.add(0);
                return;
              }
              if (!controller.isClosed) controller.addError(error);
            },
          ),

      _firestore
          .collection('Users')
          .doc(userId)
          .collection('Notifications')
          .where('type', isEqualTo: 'View')
          .snapshots()
          .listen(
            (_) => emitCount(),
            onError: (error) {
              if (_isPermissionDeniedError(error)) {
                if (!controller.isClosed) controller.add(0);
                return;
              }
              if (!controller.isClosed) controller.addError(error);
            },
          ),
    ];

    emitCount();

    controller.onCancel = () async {
      for (final sub in subscriptions) {
        await sub.cancel();
      }
    };

    return controller.stream;
  }
}
