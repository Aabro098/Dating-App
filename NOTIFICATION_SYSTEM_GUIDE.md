# Notification & Crush System Implementation Guide

## Overview

This guide explains the complete notification system that handles profile views, crushes, and favorites with proper seen status management and action priority.

---

## System Architecture

### Action Priority Hierarchy

When a user visits someone's profile, the system respects this priority:

```
Crush/Fav (Higher Priority) > View (Lower Priority)
```

**What this means:**

- If someone crushed you AND viewed your profile, only the crush is marked as seen
- If someone only viewed your profile, the view is marked as seen
- This prevents counting the same person twice if they both view and crush

### Data Structure

#### Firestore Collections

```
Users/{userId}
├── MyCrush/              (crushes I made)
│   └── {targetUserId}
│       ├── uid
│       ├── date
│       ├── seen (always false here - outgoing action)
│       └── actionType: "Crush"
├── MyFav/                (favorites I made)
│   └── {targetUserId}
│       ├── uid
│       ├── date
│       ├── seen (always false here - outgoing action)
│       └── actionType: "Fav"
├── CrushOnMe/            (crushes I received - INCOMING)
│   └── {sourcerId}
│       ├── uid
│       ├── date
│       ├── seen (marked true when viewed profile)
│       └── actionType: "Crush"
├── FavOnMe/              (favorites I received - INCOMING)
│   └── {sourcerId}
│       ├── uid
│       ├── date
│       ├── seen (marked true when viewed profile)
│       └── actionType: "Fav"
└── Notifications/        (view notifications - INCOMING)
    └── {sourcerId}View
        ├── uid
        ├── name
        ├── imgUrl
        ├── type: "View"
        ├── date
        └── seen (marked true ONLY if no Crush/Fav from same person)
```

---

## Implementation Details

### 1. Models

#### ProfileAction.dart

Updated to include action type tracking:

```dart
class ProfileAction {
  String uid;
  DateTime date;
  bool seen;
  String? actionType; // 'View', 'Crush', 'Fav'
  // ... toJson(), fromJson()
}
```

### 2. Core Methods

#### A. Mark Actions as Seen with Priority

**Location:** `DatabaseService.markIncomingProfileActionSeenWithPriority()`

```dart
/// When user visits someone's profile, this method:
/// 1. Checks if that person crushed/fav'd them (Crush > Fav > View)
/// 2. Marks the highest priority action as seen
/// 3. Ignores lower priority actions to avoid duplicates

DatabaseService.markIncomingProfileActionSeenWithPriority(
  viewerId: currentUserId,
  profileId: profileVisitedUserId,
);
```

**How it works:**

```
User A visits User B's profile
  ↓
Check if B crushed A → Mark crush as seen ✓
Check if B fav'd A → Mark fav as seen ✓
Check if B viewed A → Mark view as seen ONLY if no crush/fav exists ✗
  ↓
Result: No duplicates, proper priority
```

#### B. Add Notifications

**Location:** `NotificationService.addNotification()`

When someone views your profile:

```dart
await NotificationService.addNotification(
  receiverId,      // whose profile was viewed
  fcmToken,        // their FCM token for push notification
  "View",          // action type
  context,
);
```

#### C. Add Crush/Fav

**Location:** `DatabaseService.addCrush()` / `DatabaseService.addFav()`

```dart
// Add to both MyCrush and CrushOnMe
DatabaseService.addCrush(
  myUserId,
  ProfileAction(
    uid: targetUserId,
    date: DateTime.now(),
    seen: false,
    actionType: 'Crush',
  ),
);
```

### 3. Getting Unseen Counts

#### A. Total Unseen Count (for Nav Bar Badge)

**Location:** `ConnectionCountService.watchUnseenConnectionsCount()`

This stream emits the count of unique unseen connections:

```dart
// In your nav bar widget
StreamBuilder<int>(
  stream: ConnectionCountService.watchUnseenConnectionsCount(currentUserId),
  initialData: 0,
  builder: (context, snapshot) {
    final unseenCount = snapshot.data ?? 0;

    return Badge(
      label: Text('$unseenCount'),
      child: Icon(Icons.people),
    );
  },
);
```

**Count Includes:**

- ✅ Unseen crushes I received
- ✅ Unseen favorites I received (if not already in crushes)
- ✅ Unseen profile views (if not already in crushes/favorites)

#### B. All Connections Count (includes seen)

**Location:** `ConnectionCountService.watchAllConnectionsCount()`

For total connection count (not just unseen):

```dart
StreamBuilder<int>(
  stream: ConnectionCountService.watchAllConnectionsCount(currentUserId),
  initialData: 0,
  builder: (context, snapshot) {
    final totalConnections = snapshot.data ?? 0;
    // Display total count
  },
);
```

---

## Usage Examples

### Example 1: Display Unseen Count in Nav Bar

```dart
class ConnectionsNavItem extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<int>(
      stream: ConnectionCountService.watchUnseenConnectionsCount(currentUserId),
      initialData: 0,
      builder: (context, snapshot) {
        final unseenCount = snapshot.data ?? 0;

        return Badge(
          backgroundColor: Colors.red,
          label: Text(
            unseenCount.toString(),
            style: TextStyle(color: Colors.white),
          ),
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ConnectionsScreen()),
            ),
            child: Icon(Icons.people),
          ),
        );
      },
    );
  }
}
```

### Example 2: View Someone's Profile

When user taps to view another user's profile:

```dart
// In new_profile_view.dart (already implemented)
UserDetails? useUserDetails(String uid, BuildContext context) {
  // ...
  final viewerId = FirebaseAuth.instance.currentUser?.uid;
  if (viewerId != null) {
    // This marks crushes/favs as seen, with view as fallback
    DatabaseService.markIncomingProfileActionSeenWithPriority(viewerId, uid);
  }
  // Send view notification
  sendViewNotification(uid, user.fcmToken, context);
  // ...
}
```

### Example 3: Adding a Crush

```dart
// When user taps "Crush" button
void addCrush(String targetUserId) {
  final currentUserId = FirebaseAuth.instance.currentUser!.uid;

  final action = ProfileAction(
    uid: targetUserId,
    date: DateTime.now(),
    seen: false,
    actionType: 'Crush',
  );

  DatabaseService.addCrush(currentUserId, action);

  // Show confirmation
  showSnackBar('Crush added! 💕');
}
```

---

## Query Optimization

### Unseen Count Query

The system uses Firestore queries with proper indexing:

```
Query: Notifications (type='View' AND seen=false)
Query: CrushOnMe (seen=false)
Query: FavOnMe (seen=false)
```

**Recommended Firestore Indexes:**

- `Users > Notifications: [type, seen, date]`
- `Users > CrushOnMe: [seen, date]`
- `Users > FavOnMe: [seen, date]`

---

## State Transitions

### View Notification Flow

```
1. User A visits User B's profile
   ↓
2. sendViewNotification() → stores in Users/B/Notifications
   Notification.seen = false
   Notification.type = "View"
   ↓
3. markIncomingProfileActionSeenWithPriority() runs
   ↓
4. Check: Does B have Crush/Fav on A?
   Yes → Mark Crush/Fav as seen ✓
   No  → Mark View as seen ✓
```

### Crush Flow

```
1. User A crushes User B
   ↓
2. Stores in Users/A/MyCrush/{B} and Users/B/CrushOnMe/{A}
   Both initially seen = false
   ↓
3. When A visits B's profile later
   ↓
4. markIncomingProfileActionSeenWithPriority() runs
   → Marks CrushOnMe as seen = true
   ↓
5. B's unseen count decreases
```

---

## Troubleshooting

### Unseen Count Not Updating

**Issue:** Badge doesn't update when crush is received

**Solution:**

1. Ensure Firestore has proper indexes (see Query Optimization section)
2. Check that `seen` field is properly initialized to `false`
3. Verify stream is listening to all three collections

```dart
// Debug: Log the unseen count
ConnectionCountService.watchUnseenConnectionsCount(userId)
    .listen((count) {
      print('Unseen connections: $count');
    });
```

### Duplicates in Connection Count

**Issue:** Same person appears twice (e.g., under both crush and view)

**Solution:** This should not happen due to priority logic. If it does:

1. Check that `markIncomingProfileActionSeenWithPriority` is being called
2. Verify that `CrushOnMe` documents have `seen` field set correctly
3. Ensure old code using `markIncomingProfileActionSeen` is not being called

### Profile View Not Marking as Seen

**Issue:** User views profile, but unseen count doesn't decrease

**Solution:**

1. Verify that `ProfileAction.actionType` is being set
2. Check Firestore permissions allow update operations
3. Ensure user is viewing someone else's profile (not their own)

---

## API Reference

### ConnectionCountService

```dart
/// Get unseen connections count (one-time fetch)
static Future<int> getUnseenConnectionsCount(String userId)

/// Stream of unseen connections (real-time updates)
static Stream<int> watchUnseenConnectionsCount(String userId)

/// Get total connections count (including seen)
static Future<int> getAllConnectionsCount(String userId)

/// Stream of total connections (real-time updates)
static Stream<int> watchAllConnectionsCount(String userId)
```

### DatabaseService

```dart
/// Mark incoming actions as seen with priority logic
static Future<void> markIncomingProfileActionSeenWithPriority(
  String viewerId,
  String profileId,
)

/// Legacy method - marks all actions as seen
static Future<void> markIncomingProfileActionSeen(
  String viewerId,
  String profileId,
)

/// Add a crush
static void addCrush(String myUserId, ProfileAction action)

/// Add a favorite
static void addFav(String myUserId, ProfileAction action)
```

---

## Migration Notes

### If Upgrading from Old System

Old code using `markIncomingProfileActionSeen`:

```dart
DatabaseService.markIncomingProfileActionSeen(viewerId, uid);
```

Migrate to:

```dart
DatabaseService.markIncomingProfileActionSeenWithPriority(viewerId, uid);
```

The new method properly handles the priority hierarchy while maintaining backward compatibility.

---

## Performance Considerations

- **Stream Subscriptions:** Use `takeWhile` or `take` to limit listening time
- **Batching:** When marking multiple users as seen, batch the operations
- **Caching:** Consider caching unseen count locally and updating via stream
- **Limits:** Queries use `limit(50)` to prevent large data fetches

---

## Future Improvements

1. **Aggregation:** Add server-side aggregation for real-time unseen count
2. **Notifications:** Add push notifications when someone crushes you
3. **Analytics:** Track most-viewed profiles
4. **Blocking:** Add ability to hide views from blocked users
