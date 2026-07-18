# Complete Feature Implementation Plan — Carpooling Platform

## Executive Summary

This plan covers **18 features** across the existing Flutter + Supabase carpooling app. The codebase follows Clean Architecture (data → domain → presentation) with Riverpod for state management, GoRouter for navigation, and Supabase for backend. I will **extend** the existing architecture — not rewrite it.

### Current Codebase Analysis

| Layer | Existing | Notes |
|-------|----------|-------|
| **Database** | `profiles`, `organizations`, `vehicles`, `rides`, `bookings`, `wallets`, `wallet_transactions`, `payments`, `ride_locations`, `chat_messages`, `saved_places`, `notifications` | RLS policies + RPCs already exist |
| **Auth** | Full auth flow with signup/login, profile trigger | Working |
| **Ride** | Publish, search (v2 corridor), book (atomic RPC) | Working |
| **Trip** | Driver trips, passenger trips, start/complete/cancel, live tracking | Working |
| **Payment** | Wallet, recharge, pay (wallet/cash/card/UPI), Razorpay | Working |
| **Chat** | Send/receive messages with realtime | Working |
| **Notifications DB** | Table + triggers for booking/ride-status | Table exists, no Flutter UI |

### What's Missing

- **Booking request/accept/reject flow** (current `book_ride` RPC auto-books; no pending state)
- **Trip lifecycle timeline** (events not stored separately)
- **Feedback/review system** (no table or UI)
- **Half-ride / early exit** (no support)
- **Notification center UI** (table exists, no screen)
- **Push notifications** (no FCM integration)
- **Recurring ride matching** (data exists but no search UI)
- **Device token management** (no table)

---

## User Review Required

> [!IMPORTANT]
> **Booking Flow Change**: The existing `book_ride` RPC instantly creates a booking with status `booked`. The new flow adds a `pending` → `accepted`/`rejected` step. This means the current `book_ride` RPC will be replaced with a new `request_booking` RPC. **Old bookings will continue to work** but new ones will go through the pending flow.

> [!WARNING]
> **Push Notifications**: FCM (Firebase Cloud Messaging) requires a Firebase project. You'll need to:
> 1. Create a Firebase project (or use an existing one)
> 2. Add `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
> 3. Enable Cloud Messaging in the Firebase console
> If you don't have Firebase set up, push notifications will be skipped and only in-app notifications will work.

> [!CAUTION]
> **New Dependencies**: This plan adds `firebase_core`, `firebase_messaging`, and `flutter_local_notifications` packages. These require native platform setup (Android manifest changes, iOS entitlements).

---

## Open Questions

> [!IMPORTANT]
> 1. **Firebase Project**: Do you already have a Firebase project set up for this app? If not, should I skip push notifications for now and implement only in-app notifications?
> 2. **Payment for Half Ride**: Should the recalculated fare use the same per-km rate from the organization, or the original `fare_per_seat`?
> 3. **Booking Expiry**: Should pending booking requests auto-expire after a timeout (e.g., 10 minutes)?
> 4. **Live Location for Passengers**: Should passengers also broadcast their location to the driver, or only the driver broadcasts?

---

## Implementation Phases

### Phase 1 — Database Schema Extensions
### Phase 2 — Booking Request/Accept/Reject + Notifications Foundation
### Phase 3 — Trip Lifecycle + Payment + Feedback
### Phase 4 — Notification Center + Push Notifications
### Phase 5 — Half Ride + Recurring Ride Matching
### Phase 6 — Live Location + Ride Tracking Enhancements

---

## Proposed Changes

### Phase 1: Database Schema Extensions

#### [NEW] [feature_migration.sql](file:///Users/sudhanshukumar/Desktop/car_pooling/supabase/feature_migration.sql)

New SQL migration file adding all required schema changes:

**1. Modify `bookings` table** — Add `pending` and `accepted`/`rejected` statuses:
```sql
ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_status_check;
ALTER TABLE bookings ADD CONSTRAINT bookings_status_check 
  CHECK (status IN ('pending','accepted','booked','in_progress','completed',
                    'cancelled','rejected','payment_pending','payment_completed'));
```

**2. New `trip_lifecycle` table** — Event log for every status transition:
```sql
CREATE TABLE trip_lifecycle (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  booking_id UUID REFERENCES bookings(id) ON DELETE CASCADE,
  event TEXT NOT NULL,
  actor_id UUID REFERENCES profiles(id),
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**3. New `feedback` table**:
```sql
CREATE TABLE feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL REFERENCES rides(id),
  booking_id UUID NOT NULL REFERENCES bookings(id),
  reviewer_id UUID NOT NULL REFERENCES profiles(id),
  reviewee_id UUID NOT NULL REFERENCES profiles(id),
  rating INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**4. New `device_tokens` table**:
```sql
CREATE TABLE device_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('android','ios','web')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, token)
);
```

**5. Add `notifications` columns** for rich notification support:
```sql
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS sender_id UUID REFERENCES profiles(id);
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'system';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS deep_link TEXT;
```

**6. New RPCs**:
- `request_booking(p_ride_id, p_seats)` — Creates booking with status `pending`
- `accept_booking(p_booking_id)` — Driver accepts: `pending` → `accepted`, decrements seats
- `reject_booking(p_booking_id)` — Driver rejects: `pending` → `rejected`
- `log_lifecycle_event(...)` — Logs a trip lifecycle event
- `submit_feedback(...)` — Submits a review
- `end_ride_early(p_booking_id, p_new_fare)` — Half-ride early exit

**7. New triggers**:
- On booking status change → insert notification + lifecycle event
- On feedback insert → notify reviewee

**8. RLS policies** for all new tables

**9. Realtime** enabled for `trip_lifecycle`, `feedback`, `notifications`

---

### Phase 2: Booking Request/Accept/Reject + Notification Foundation

#### [MODIFY] [booking_entity.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/ride/domain/entities/booking_entity.dart)
- Add `pending`, `accepted`, `rejected` to status comment
- No structural changes needed (status is already a `String`)

#### [MODIFY] [ride_remote_datasource.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/ride/data/datasources/ride_remote_datasource.dart)
- Change `bookRide()` to call `request_booking` RPC instead of `book_ride`
- Returns booking with status `pending`

#### [MODIFY] [ride_repository.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/ride/data/repositories/ride_repository.dart)
- Update `bookRide()` signature doc-comment

#### [NEW] [notification_entity.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/notification/domain/entities/notification_entity.dart)
- `NotificationEntity` with fields: `id`, `userId`, `senderId`, `title`, `body`, `type`, `category`, `data`, `deepLink`, `isRead`, `createdAt`, `readAt`
- `fromMap()` factory

#### [NEW] [notification_remote_datasource.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/notification/data/datasources/notification_remote_datasource.dart)
- `getNotifications({int limit, int offset})` — paginated
- `getUnreadCount()` 
- `markAsRead(String id)` 
- `markAllAsRead()` 
- `deleteNotification(String id)`
- `subscribeToNotifications(callback)` — realtime
- `respondToBooking(String bookingId, bool accept)` — calls `accept_booking` or `reject_booking` RPC

#### [NEW] [notification_repository.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/notification/data/repositories/notification_repository.dart)
- Wraps datasource, same pattern as `TripRepository`

#### [NEW] [notification_provider.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/notification/presentation/providers/notification_provider.dart)
- `notificationDataSourceProvider`
- `notificationRepositoryProvider`
- `notificationsProvider` — `FutureProvider` for the list
- `unreadCountProvider` — `StreamProvider<int>` from realtime
- `NotificationActionNotifier` — mark read, delete, respond to booking

#### [NEW] [notification_center_screen.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/notification/presentation/screens/notification_center_screen.dart)
- Full notification center with:
  - Grouped by category (Booking, Ride, Payment, Chat, System)
  - Read/unread visual distinction
  - Mark all as read button
  - Swipe to delete
  - Tap to navigate (deep link)
  - Accept/Reject buttons for pending booking notifications
  - Empty state, loading state, error state

#### [MODIFY] [route_names.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/core/constants/route_names.dart)
- Add `notifications`, `feedback`, `rideTracking`

#### [MODIFY] [app_router.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/core/router/app_router.dart)
- Add routes for notification center, feedback screen, ride tracking screen
- Add `notifications` to the ShellRoute (bottom nav)

#### [MODIFY] [dashboard_screen.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/dashboard/presentation/screens/dashboard_screen.dart)
- Add notification bell icon with unread badge count in app bar
- Add "Notifications" tab to bottom navigation

---

### Phase 3: Trip Lifecycle + Payment + Feedback

#### [NEW] [lifecycle_entity.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/trip/domain/entities/lifecycle_entity.dart)
- `LifecycleEvent` entity: `id`, `rideId`, `bookingId`, `event`, `actorId`, `metadata`, `createdAt`

#### [MODIFY] [trip_remote_datasource.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/trip/data/datasources/trip_remote_datasource.dart)
- Add `getLifecycleEvents(String rideId)` — fetch timeline
- Add `logLifecycleEvent(...)` — manual event logging
- Update `startRide()`, `completeRide()` to also log lifecycle events
- Add `acceptBooking(String bookingId)` and `rejectBooking(String bookingId)`

#### [MODIFY] [trip_repository.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/trip/data/repositories/trip_repository.dart)
- Expose lifecycle and booking response methods

#### [MODIFY] [trip_provider.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/trip/presentation/providers/trip_provider.dart)
- Add `lifecycleProvider(String rideId)` — `FutureProvider.family`
- Add `acceptBooking()` and `rejectBooking()` to `TripActionNotifier`

#### [MODIFY] [trip_details_screen.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/trip/presentation/screens/trip_details_screen.dart)
- Add lifecycle timeline widget (vertical stepper)
- Add accept/reject buttons for pending bookings (driver view)
- Add booking status badge for passenger view

#### [NEW] [feedback_entity.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/feedback/domain/entities/feedback_entity.dart)
- `FeedbackEntity`: `id`, `rideId`, `bookingId`, `reviewerId`, `revieweeId`, `rating`, `comment`, `createdAt`

#### [NEW] [feedback_remote_datasource.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/feedback/data/datasources/feedback_remote_datasource.dart)
- `submitFeedback(...)` 
- `getFeedbackForUser(String userId)` 
- `getFeedbackForRide(String rideId)`

#### [NEW] [feedback_provider.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/feedback/presentation/providers/feedback_provider.dart)
- `feedbackDataSourceProvider`
- `FeedbackNotifier` — submit action with loading state

#### [NEW] [feedback_screen.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/feedback/presentation/screens/feedback_screen.dart)
- Star rating (1-5) with animated stars
- Comment text field
- Submit button with loading state
- Success animation on submit

#### [MODIFY] [payment_method_screen.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/payment/presentation/screens/payment_method_screen.dart)
- After successful payment, navigate to feedback screen
- Add ride summary card (pickup, destination, distance, fare)

#### [MODIFY] [trip_finish_screen.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/trip/presentation/screens/trip_finish_screen.dart)
- Update to show ride summary before payment
- Add UPI payment option prominently

---

### Phase 4: Notification Center + Push Notifications (Optional)

#### [NEW] [push_notification_service.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/core/services/push_notification_service.dart)
- Initialize FCM
- Request notification permissions
- Get/refresh device token
- Save token to `device_tokens` table
- Handle foreground/background/terminated message routing
- Show local notification when app is in foreground
- Navigate to correct screen on notification tap

#### [MODIFY] [main.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/main.dart)
- Initialize push notification service after Supabase init
- Register device token on login

#### [MODIFY] [auth_provider.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/auth/presentation/providers/auth_provider.dart)
- On sign-in success, register device token
- On sign-out, remove device token

> [!NOTE]
> If Firebase is not set up, push notification service will gracefully degrade. All in-app notifications will still work via Supabase Realtime.

---

### Phase 5: Half Ride + Recurring Ride Matching

#### [MODIFY] [trip_remote_datasource.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/trip/data/datasources/trip_remote_datasource.dart)
- Add `requestEarlyExit(String bookingId, double newFare)` — passenger requests to end early
- Add `respondToEarlyExit(String bookingId, bool accept)` — driver accepts/rejects

#### [MODIFY] [trip_details_screen.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/trip/presentation/screens/trip_details_screen.dart)
- Add "End Ride Early" button for passenger during `in_progress`
- Show fare recalculation dialog
- For driver: show early exit request notification with accept/reject

#### [MODIFY] [ride_remote_datasource.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/ride/data/datasources/ride_remote_datasource.dart)
- Add `searchRecurringRides(...)` — searches by matching recurring days

#### [MODIFY] [ride_repository.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/ride/data/repositories/ride_repository.dart)
- Add `searchRecurringRides(...)` — sorts by match count (exact first, then descending)

#### [MODIFY] [ride_provider.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/ride/presentation/providers/ride_provider.dart)
- Add `recurringRidesProvider` — FutureProvider for recurring search

#### [MODIFY] [available_rides_screen.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/ride/presentation/screens/available_rides_screen.dart)
- Add toggle for "Recurring Ride Search"
- Show "Exact Matches" and "Other Suggested Matches" sections
- Display match count badge on each ride card

#### [MODIFY] [route_confirmation_screen.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/ride/presentation/screens/route_confirmation_screen.dart)
- Recurring ride toggle already exists in form; ensure days selector is shown when toggled

---

### Phase 6: Live Location + Ride Tracking Enhancements

#### [MODIFY] [live_tracking_screen.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/trip/presentation/screens/live_tracking_screen.dart)
- Add both rider and driver location markers
- Show route polyline
- Display ETA and remaining distance in real-time
- Auto-update location every 5 seconds
- Show ride status badge
- Show payment status (if completed)
- Auto-stop tracking when ride completes

#### [MODIFY] [trip_remote_datasource.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/trip/data/datasources/trip_remote_datasource.dart)
- Add `publishPassengerLocation(...)` — for passenger location sharing
- Add `subscribeToPassengerLocations(...)` — driver sees passenger positions

---

## New File Structure

```
lib/features/
├── notification/
│   ├── data/
│   │   └── datasources/
│   │       └── notification_remote_datasource.dart
│   ├── domain/
│   │   └── entities/
│   │       └── notification_entity.dart
│   └── presentation/
│       ├── providers/
│       │   └── notification_provider.dart
│       └── screens/
│           └── notification_center_screen.dart
├── feedback/
│   ├── data/
│   │   └── datasources/
│   │       └── feedback_remote_datasource.dart
│   ├── domain/
│   │   └── entities/
│   │       └── feedback_entity.dart
│   └── presentation/
│       ├── providers/
│       │   └── feedback_provider.dart
│       └── screens/
│           └── feedback_screen.dart
└── trip/
    └── domain/
        └── entities/
            └── lifecycle_entity.dart   [NEW]

lib/core/services/
    └── push_notification_service.dart  [NEW]

supabase/
    └── feature_migration.sql           [NEW]
```

---

## Verification Plan

### Automated Tests
```bash
cd app && flutter analyze
cd app && flutter build apk --debug  # Verify no compile errors
```

### Manual Verification
1. **Booking Flow**: Passenger requests → Driver sees notification → Accept → Passenger sees accepted status → Ride lifecycle updates
2. **Reject Flow**: Driver rejects → Passenger sees rejection notification
3. **Trip Lifecycle**: Start → Track → Complete → Timeline shows all events
4. **Payment**: Complete ride → Payment screen → Pay via UPI/wallet → Success
5. **Feedback**: After payment → Rating + comment → Driver receives notification
6. **Half Ride**: Passenger requests early exit → Driver accepts → Fare recalculated → Payment
7. **Notifications**: All events generate in-app notifications → Badge count updates → Tap navigates correctly
8. **Recurring Rides**: Offer recurring ride → Search with matching days → See exact and partial matches
9. **Live Tracking**: Both users see each other's location → ETA updates → Auto-stops on completion

### Performance
- Supabase Realtime for notifications, chat, location, booking status — no polling
- Pagination for notification history (20 per page)
- `autoDispose` on all screen-scoped providers
- Subscription cleanup on screen dispose
