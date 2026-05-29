# Step-by-Step Integration Guide

## Quick Start: Add Unseen Count Badge to Nav Bar

### Step 1: Import the Badge Component

Add this to your nav bar file:

```dart
import 'package:viora/components/ConnectionsBadge.dart';
import 'package:viora/Services/connection_count_service.dart';
```

### Step 2: Add Badge to Your Nav Bar

#### Option A: Using Persistent Bottom Nav Bar (Your Current Setup)

In your main navigation widget, add the `ConnectionsBadge`:

```dart
PersistentBottomNavBar(
  items: [
    PersistentBottomNavBarItem(
      icon: Icon(Icons.home),
      title: "Home",
      activeColorPrimary: Colors.blue,
      inactiveColorPrimary: Colors.grey,
    ),
    PersistentBottomNavBarItem(
      // Use ConnectionsBadge here
      icon: ConnectionsBadge(
        onTap: () {
          // Handle connections tap
          _navController.jumpToTab(1); // Navigate to connections tab
        },
      ),
      title: "Connections",
      activeColorPrimary: Colors.blue,
      inactiveColorPrimary: Colors.grey,
    ),
    PersistentBottomNavBarItem(
      icon: Icon(Icons.person),
      title: "Profile",
      activeColorPrimary: Colors.blue,
      inactiveColorPrimary: Colors.grey,
    ),
  ],
  // ... other properties
)
```

#### Option B: Using Bottom Navigation Bar

```dart
BottomNavigationBar(
  items: [
    BottomNavigationBarItem(
      icon: Icon(Icons.home),
      label: 'Home',
    ),
    BottomNavigationBarItem(
      icon: ConnectionsBadge(
        onTap: () => setState(() => _selectedIndex = 1),
      ),
      label: 'Connections',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.person),
      label: 'Profile',
    ),
  ],
  currentIndex: _selectedIndex,
  onTap: (index) => setState(() => _selectedIndex = index),
)
```

### Step 3: Create Connections Screen

Show the list of connections with unseen count:

```dart
class ConnectionsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: Text('Connections')),
      body: Column(
        children: [
          // Show unseen count at top
          StreamBuilder<int>(
            stream: ConnectionCountService.watchUnseenConnectionsCount(userId),
            builder: (context, snapshot) {
              final unseenCount = snapshot.data ?? 0;

              if (unseenCount == 0) return SizedBox.shrink();

              return Container(
                color: Colors.blue.shade100,
                padding: EdgeInsets.all(12),
                child: Text(
                  'You have $unseenCount new connection${unseenCount == 1 ? '' : 's'}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
          // List of connections...
        ],
      ),
    );
  }
}
```

---

## Manual Integration (If Not Using Component)

### Step 1: Add Direct Stream Builder

If you prefer not to use the component, add this directly to your nav bar:

```dart
StreamBuilder<int>(
  stream: ConnectionCountService.watchUnseenConnectionsCount(userId),
  initialData: 0,
  builder: (context, snapshot) {
    final unseenCount = snapshot.data ?? 0;

    return Stack(
      alignment: Alignment.topRight,
      children: [
        Icon(Icons.people, size: 24),
        if (unseenCount > 0)
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              unseenCount > 99 ? '99+' : '$unseenCount',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  },
)
```

---

## Verifying the Implementation

### Test Case 1: View Profile

1. Open User B's profile as User A
2. Expected: User B sees "seen" status updated for their received notifications
3. Expected: User B's unseen count decreases

### Test Case 2: Send a Crush

1. User A crushes User B
2. Expected: Crush notification appears in User B's system
3. Expected: User B's unseen count includes this crush
4. When User B views User A's profile:
   - Expected: Crush marked as seen (not view)
   - Expected: Unseen count decreases

### Test Case 3: View + Crush

1. User A receives crush from User B
2. User B views User A's profile
3. Expected: Only crush is marked as seen
4. Expected: View notification is NOT marked as seen
5. User A's unseen count should show 1 (not 2)

### Debug Output

Add this to see real-time unseen count changes:

```dart
// In initState or anywhere you want to debug
final userId = FirebaseAuth.instance.currentUser!.uid;

ConnectionCountService.watchUnseenConnectionsCount(userId)
    .listen((count) {
      print('📊 Unseen connections count: $count');
    });
```

---

## Testing Locally

### Firestore Emulator (Recommended)

If using Firebase emulator:

```dart
// In DatabaseService or Firebase config
if (kDebugMode) {
  FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  // ... other emulator settings
}
```

### Firebase Console

Monitor in real-time:

1. Go to Firestore console
2. Navigate to `Users/{userId}/CrushOnMe`
3. Verify `seen` field changes when profile is visited
4. Check `Notifications` collection for view entries

---

## Troubleshooting

### Issue: Badge Shows 0 Always

**Cause:** No data in CrushOnMe/FavOnMe/Notifications collections

**Solution:**

1. Create test data manually in Firestore:

```
Users/testUserId/CrushOnMe/senderUserId
{
  "uid": "senderUserId",
  "date": timestamp,
  "seen": false,
  "actionType": "Crush"
}
```

2. Refresh the stream:

```dart
// Force refresh
await ConnectionCountService.getUnseenConnectionsCount(userId);
```

### Issue: Count Doesn't Update After Viewing Profile

**Cause:** `markIncomingProfileActionSeenWithPriority` not being called

**Solution:**

1. Check `new_profile_view.dart` has the correct import
2. Verify method is called in `useUserDetails` hook
3. Check Firestore security rules allow update operations
4. Check browser console for errors

### Issue: Duplicate Entries in Count

**Cause:** Both view and crush being counted

**Solution:**

1. Verify crush/fav marked as seen when visiting profile
2. Check that `watchUnseenConnectionsCount` skips already-added UIDs
3. Review set deduplication logic in `getUnseenConnectionsCount`

### Issue: Performance Slow with Many Connections

**Cause:** Querying too many documents

**Solution:**

1. Reduce the `limit(50)` in queries if needed
2. Add Firestore indexes (see NOTIFICATION_SYSTEM_GUIDE.md)
3. Consider paginating the connections list
4. Cache the count locally and update via stream

---

## Performance Tips

### Optimize Stream Listening

```dart
// ✅ Good: Unsubscribe when not needed
late StreamSubscription _subscription;

@override
void initState() {
  super.initState();
  _subscription = ConnectionCountService
      .watchUnseenConnectionsCount(userId)
      .listen((count) {
        setState(() => unseenCount = count);
      });
}

@override
void dispose() {
  _subscription.cancel();
  super.dispose();
}
```

### Use StreamBuilder Instead

```dart
// ✅ Better: StreamBuilder handles subscriptions automatically
StreamBuilder<int>(
  stream: ConnectionCountService.watchUnseenConnectionsCount(userId),
  builder: (context, snapshot) {
    // Automatically subscribed/unsubscribed
  },
)
```

### Batch Mark as Seen

```dart
// ✅ If marking multiple connections as seen
Future<void> markMultipleAsSeen(List<String> uids) async {
  for (final uid in uids) {
    await DatabaseService.markIncomingProfileActionSeenWithPriority(
      FirebaseAuth.instance.currentUser!.uid,
      uid,
    );
  }
}
```

---

## API Methods Reference

### Get Unseen Count (One-time)

```dart
final count = await ConnectionCountService.getUnseenConnectionsCount(userId);
print('Unseen: $count');
```

### Stream Unseen Count (Real-time)

```dart
final stream = ConnectionCountService.watchUnseenConnectionsCount(userId);
stream.listen((count) {
  print('Unseen updated: $count');
});
```

### Mark Actions as Seen with Priority

```dart
await DatabaseService.markIncomingProfileActionSeenWithPriority(
  currentUserId,
  viewedProfileUserId,
);
```

### Add Crush

```dart
final action = ProfileAction(
  uid: targetUserId,
  date: DateTime.now(),
  seen: false,
  actionType: 'Crush',
);
DatabaseService.addCrush(currentUserId, action);
```

---

## Next Steps

1. **Implement Badge:** Add `ConnectionsBadge` to your nav bar
2. **Create Screen:** Build connections list screen
3. **Test:** Follow test cases above
4. **Monitor:** Watch Firestore for data changes
5. **Optimize:** Add indexes if needed
6. **Deploy:** Push to production

---

## Questions?

For implementation issues:

1. Check NOTIFICATION_SYSTEM_GUIDE.md for detailed architecture
2. Review the component examples in ConnectionsBadge.dart
3. Test with Firestore emulator first
4. Check browser console for errors

For data issues:

1. Verify documents exist in Firestore
2. Check `seen` field is boolean (not string)
3. Verify user permissions in security rules
4. Monitor in Firestore console
