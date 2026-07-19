# Firebase Cloud Messaging (FCM) — Setup Guide

This app already stores per-user push tokens in the `device_tokens`
table (populated by `notification_remote_datasource.registerDeviceToken`).
The pieces below add the actual delivery pipeline so users receive push
notifications on their phones even when the app is closed.

There are three layers to wire up:

1. Firebase project + platform config files (iOS + Android).
2. Flutter side — request permission, register token, foreground handler.
3. Server side — a Supabase Edge Function that reads the `notifications`
   table and dispatches a push to every device token belonging to the
   recipient.

---

## 1. Firebase Project

1. Go to <https://console.firebase.google.com> and create a project
   (any name, disable Analytics if you don't need it).
2. Add an **Android app**: package name `com.example.car_pooling`
   (change to match `android/app/build.gradle.kts`).  
   Download `google-services.json` → place in `app/android/app/`.
3. Add an **iOS app**: bundle id from `ios/Runner.xcodeproj`.  
   Download `GoogleService-Info.plist` → place in `app/ios/Runner/`.
4. In **Project settings → Cloud Messaging**, note the *Sender ID* and
   generate a **Service account key** JSON (Project settings → Service
   accounts → *Generate new private key*). We'll paste this into a
   Supabase secret.

### Android Gradle wiring

`app/android/build.gradle.kts`:

```kotlin
plugins {
    id("com.google.gms.google-services") version "4.4.2" apply false
}
```

`app/android/app/build.gradle.kts`:

```kotlin
plugins {
    id("com.google.gms.google-services")
}
```

### iOS

Open `ios/Runner.xcworkspace` in Xcode, drag `GoogleService-Info.plist`
into the Runner target, then enable **Push Notifications** and
**Background Modes → Remote notifications** in the *Signing &
Capabilities* tab.

---

## 2. Flutter Integration

Add to `app/pubspec.yaml`:

```yaml
dependencies:
  firebase_core: ^3.6.0
  firebase_messaging: ^15.1.3
  flutter_local_notifications: ^17.2.3
```

`flutter pub get`, then:

`app/lib/main.dart`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  // Nothing to do — the system tray will show it automatically.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
  // ...existing Supabase init and runApp
}
```

`app/lib/features/notification/data/services/push_service.dart` (new):

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../datasources/notification_remote_datasource.dart';

class PushService {
  final NotificationRemoteDataSource _ds;
  final _local = FlutterLocalNotificationsPlugin();
  PushService(this._ds);

  Future<void> init() async {
    await _local.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
    final fm = FirebaseMessaging.instance;
    await fm.requestPermission();
    final token = await fm.getToken();
    if (token != null) await _ds.registerDeviceToken(token);
    fm.onTokenRefresh.listen(_ds.registerDeviceToken);

    FirebaseMessaging.onMessage.listen((msg) {
      final n = msg.notification;
      if (n == null) return;
      _local.show(
        n.hashCode,
        n.title,
        n.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default', 'General',
            importance: Importance.high, priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    });
  }
}
```

Call `PushService(...).init()` right after the user successfully signs
in (inside `AuthNotifier.signIn` on success, for example).

---

## 3. Supabase Edge Function → FCM

Store the service-account JSON as a secret:

```bash
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat firebase-sa.json)"
supabase secrets set FIREBASE_PROJECT_ID="your-project-id"
```

Create `supabase/functions/push-notification/index.ts`:

```ts
import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const sa = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);
const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;

async function getAccessToken(): Promise<string> {
  // Sign a JWT with the SA private key and exchange it for a Google
  // OAuth token. Use e.g. the `google-auth-library` port for Deno,
  // or implement RS256 signing with djwt.
  // See: https://firebase.google.com/docs/cloud-messaging/auth-server
  throw new Error("Implement token exchange with djwt or an npm helper");
}

serve(async (req) => {
  const { record } = await req.json();           // Postgres webhook payload
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: tokens } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("user_id", record.user_id);
  if (!tokens || tokens.length === 0) return new Response("no tokens");

  const accessToken = await getAccessToken();
  await Promise.all(tokens.map(({ token }) =>
    fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: record.title, body: record.body },
          data: {
            type: record.type ?? "",
            deep_link: record.deep_link ?? "",
            ...(record.data ?? {}),
          },
        },
      }),
    })
  ));
  return new Response("ok");
});
```

Deploy:

```bash
supabase functions deploy push-notification --no-verify-jwt
```

Add a **Database Webhook** (Supabase dashboard → Database → Webhooks):

- Table: `notifications`
- Events: **Insert**
- Type: `Supabase Edge Functions`
- Function: `push-notification`

Every new row in `notifications` now fans out to every device the
recipient has logged in on. The RPCs in `feature_migration.sql` /
`feature_fixes.sql` already create those rows on booking, ride, and
payment events, so no other code changes are needed once the function
is deployed.

---

## Testing

1. Run the app on a real Android device (emulator FCM works, iOS
   simulator doesn't).
2. Sign in — check the `device_tokens` table has your row.
3. From another account, send yourself a booking request. You should
   see a system notification within a couple of seconds.
