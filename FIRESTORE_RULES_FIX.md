# Fix Firestore Permission Denied for Messages

The error `PERMISSION_DENIED` when opening chat happens because Firestore rules don't allow updating the `seen` field on Messages.

## Fix in Firebase Console

1. Go to **Firebase Console** → your project → **Firestore Database** → **Rules**
2. Find the `Messages` collection rule (or add it if missing)
3. Ensure you have an **update** rule that allows the **receiver** to mark messages as seen:

```
match /Messages/{messageId} {
  // Allow create: any authenticated user can send
  allow create: if request.auth != null;
  // Allow read: sender or receiver can read
  allow read: if request.auth != null && 
    (resource.data.uid == request.auth.uid || resource.data.receiver == request.auth.uid);
  // Allow update: only receiver can mark as seen
  allow update: if request.auth != null && resource.data.receiver == request.auth.uid;
  allow delete: if false;
}
```

4. Click **Publish**

## Does this affect notifications?

**No.** Push notifications use FCM/Cloud Functions, not Firestore. The permission error only affects:
- Marking messages as "seen" when you open a chat
- The unhandled exception spam in logs

The code has been updated to catch this error gracefully so it won't crash the app.
