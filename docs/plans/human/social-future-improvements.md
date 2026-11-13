# Social Activity Feed - Future Improvements

> **Status:** Ideas for future iterations
> **Created:** 2026-01-28

These features were identified during the initial Social Activity Feed implementation but deferred to keep scope manageable.

## 1. Friend Invite Links ✅ DONE

**Problem:** API supports invite links (`GET /v1/friends/invite-link`) but no UI to generate or share them.

**Solution:**
- Add "Invite Friend" button to FriendsListView
- Generate link via API
- Present iOS share sheet with the link
- Handle incoming invite links via URL scheme / universal links

**Effort:** Medium (includes deep link handling)

---

## 2. Friend Profile View ✅ DONE

**Problem:** Design mentioned FriendProfileView for viewing a friend's stats and activity, but wasn't implemented.

**Solution:**
- Create FriendProfileView showing:
  - Callsign and display name
  - Their recent activity (filtered feed)
  - Basic stats if available
- Make callsign tappable in ActivityItemRow to navigate to profile

**Effort:** Medium

---

## 3. QSO Friend Suggestions

**Problem:** After logging a QSO with someone who is a Carrier Wave user, we could prompt to add them as a friend.

**Solution:**
- After QSO sync, check if worked callsign is a registered user
- Show subtle prompt or badge
- Requires new API endpoint to check if callsign is a user

**Effort:** Medium (needs backend support)

---

## 4. Push Notifications

**Problem:** Currently polling-based. Users don't get notified of friend requests or notable friend activity.

**Solution:**
- Implement push notification infrastructure
- Notify on: friend request received, friend request accepted, notable friend activity

**Effort:** Large (needs backend push infrastructure)

---

## Priority Recommendation

1. **Friend Invite Links** - Improves friend discovery
2. **Friend Profile View** - Enhances social experience
3. **QSO Friend Suggestions** - Nice-to-have
4. **Push Notifications** - Largest effort, defer until user demand
