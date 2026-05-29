# Quick Reference Card

## 🎯 Your Notification System at a Glance

### The Problem Solved

✅ Profile views tracked with seen status  
✅ Crushes tracked with seen status  
✅ Action priority: Crush > Fav > View  
✅ Display unseen count in nav bar  
✅ No duplicates: same person counted once

---

## 🚀 Implementation in 3 Steps

### Step 1: Add Component to Nav Bar

```dart
import 'package:viora/components/ConnectionsBadge.dart';

// In your nav bar
ConnectionsBadge(
  onTap: () => Navigator.push(context, MaterialPageRoute(...))
)
```

### Step 2: Create Connections Screen

Display the list of people who viewed/crushed you

### Step 3: That's It!

The system auto-updates when profiles are visited

---

## 📊 Real-Time Count

```dart
// Automatically updates when data changes
ConnectionCountService.watchUnseenConnectionsCount(userId)
```

**Shows:**

- Unseen crushes you received ✓
- Unseen favorites you received ✓
- Unseen views (only if no crush/fav) ✓

---

## 🔄 Action Flow

```
User A visits User B's profile
  ↓
Check: Did B crush/fav A?
  ├─ YES → Mark crush/fav as seen
  └─ NO → Mark view as seen
  ↓
User B's unseen count updates
```

---

## 📁 Key Files

| File                          | Purpose                                                        |
| ----------------------------- | -------------------------------------------------------------- |
| `ProfileAction.dart`          | Model with actionType field                                    |
| `DatabaseService.dart`        | `markIncomingProfileActionSeenWithPriority()`                  |
| `ConnectionCountService.dart` | `getUnseenConnectionsCount()`, `watchUnseenConnectionsCount()` |
| `ConnectionsBadge.dart`       | Ready-to-use component                                         |

---

## 🔧 API Methods

### Get Unseen Count

```dart
// One-time
final count = await ConnectionCountService.getUnseenConnectionsCount(userId);

// Real-time stream
final stream = ConnectionCountService.watchUnseenConnectionsCount(userId);
```

### Mark as Seen

```dart
DatabaseService.markIncomingProfileActionSeenWithPriority(
  currentUserId,
  viewedProfileUserId,
);
```

### Add Crush/Fav

```dart
DatabaseService.addCrush(
  myUserId,
  ProfileAction(uid: targetUserId, date: now()),
);
```

---

## ⚡ Performance Tips

- ✅ Use `StreamBuilder` (auto cleanup)
- ✅ Firestore indexes for queries (see NOTIFICATION_SYSTEM_GUIDE.md)
- ✅ Limit queries to 50 documents
- ✅ Batch operations when possible

---

## 🧪 Test This

1. Create test users
2. Have User A crush User B
3. Have User A visit User B's profile
4. Check: Only crush marked as seen (not view)
5. Verify unseen count shows 1 (not 2)

---

## 📚 Full Documentation

- **Architecture**: [NOTIFICATION_SYSTEM_GUIDE.md](NOTIFICATION_SYSTEM_GUIDE.md)
- **Setup**: [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)
- **Summary**: [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)

---

## 🆘 Quick Troubleshooting

| Problem              | Solution                                                  |
| -------------------- | --------------------------------------------------------- |
| Badge shows 0        | Add test crushes in Firestore                             |
| Count doesn't update | Use StreamBuilder                                         |
| Duplicate count      | Verify `markIncomingProfileActionSeenWithPriority` called |
| Performance slow     | Add Firestore indexes                                     |

---

## 💡 Key Insight

**Priority Hierarchy prevents duplicates:**

- Same person crush + view = counted once as crush
- Not as crush AND view = avoiding confusion

---

## ✨ What's New

| Feature            | Before | After              |
| ------------------ | ------ | ------------------ |
| Action tracking    | Basic  | With priority      |
| Unseen display     | Manual | Real-time stream   |
| Duplicate handling | None   | Automatic dedup    |
| Priority logic     | None   | Crush > Fav > View |

---

## 🎓 Example Scenarios

### Scenario 1: View Only

```
A visits B → B's unseen count: +1 (View)
A views B's profile → B's unseen count: 0
```

### Scenario 2: Crush Only

```
A crushes B → B's unseen count: +1 (Crush)
A views B's profile → B's unseen count: 0
```

### Scenario 3: Crush + View (The Key!)

```
A crushes B → B's unseen count: +1 (Crush)
A views B → Mark crush as seen, NOT view
B's unseen count: 0 (not counted as 2)
```

---

## 📦 What's Included

- ✅ 4 modified service/model files
- ✅ 1 new UI component
- ✅ 3 comprehensive guides
- ✅ Real-time stream support
- ✅ Backward compatible

---

## 🎯 Next Action

**Add to nav bar → Test → Deploy**

```dart
// Copy this into your nav bar
ConnectionsBadge(onTap: () { /* navigate */ })
```

Done! ✅
