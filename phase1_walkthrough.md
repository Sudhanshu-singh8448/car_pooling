# Phase 1 — Foundation & Authentication — Completion Walkthrough

> **Status**: ✅ Complete | **Files**: 17 | **Lines of Code**: 2,109 | **Analyze**: 0 issues | **Tests**: All passing

---

## What Was Built

Phase 1 delivers the complete foundation: project scaffolding, design system, authentication (Supabase), navigation (GoRouter), and the main dashboard shell with bottom navigation — everything needed to start building ride features in Phase 2.

---

## Architecture Decisions

| Decision | Choice | Rationale |
|---|---|---|
| **Framework** | Flutter 3.44.6 | Cross-platform, compiled performance, great maps support |
| **Backend** | Supabase | PostgreSQL + Auth + Realtime out of the box — fastest path for hackathon |
| **State Management** | Riverpod (StateNotifier) | Type-safe, composable, built-in DI, testable |
| **Navigation** | GoRouter | Declarative routing with auth redirects, ShellRoute for bottom nav |
| **Architecture** | Clean Architecture (feature-first) | Domain/Data/Presentation separation per feature |

---

## Project Structure (Phase 1)

```
app/lib/
├── main.dart                                           # Entry point, Supabase init, ProviderScope
│
├── core/
│   ├── constants/
│   │   ├── app_constants.dart                          # API keys, durations, pagination
│   │   └── route_names.dart                            # All route path constants
│   ├── router/
│   │   └── app_router.dart                             # GoRouter config with auth redirects
│   ├── theme/
│   │   ├── app_colors.dart                             # Color palette (primary, semantic, status)
│   │   ├── app_spacing.dart                            # Spacing & border radius tokens
│   │   ├── app_theme.dart                              # Material3 ThemeData configuration
│   │   └── app_typography.dart                         # Google Fonts (Inter) text styles
│   └── utils/
│       └── validators.dart                             # Form validators (email, phone, password)
│
├── features/
│   ├── auth/
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   │   └── auth_remote_datasource.dart         # Supabase Auth API calls
│   │   │   └── repositories/
│   │   │       └── auth_repository.dart                # Repository abstraction
│   │   ├── domain/
│   │   │   └── entities/
│   │   │       └── user_entity.dart                    # User domain model with Equatable
│   │   └── presentation/
│   │       ├── providers/
│   │       │   └── auth_provider.dart                  # AuthNotifier + all DI providers
│   │       └── screens/
│   │           ├── splash_screen.dart                  # Animated splash with auth check
│   │           ├── login_screen.dart                   # Login form with validation
│   │           └── signup_screen.dart                  # Registration form with avatar
│   │
│   └── dashboard/
│       └── presentation/
│           └── screens/
│               └── dashboard_screen.dart               # Shell with AppBar + bottom nav
```

---

## File-by-File Details

### Core Infrastructure

#### [main.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/main.dart)
- Initializes Supabase with URL + publishable key
- Locks portrait orientation, sets transparent status bar
- Wraps app in Riverpod `ProviderScope`
- Uses `MaterialApp.router` with GoRouter

#### [app_router.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/core/router/app_router.dart)
- Auth-aware redirect logic: unauthenticated users → Login, authenticated users skip auth screens
- `ShellRoute` for bottom navigation (Dashboard, My Trips, History, Vehicle, Settings)
- Placeholder screens for tabs built in later phases

#### [app_constants.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/core/constants/app_constants.dart)
- Supabase URL/key placeholders (to be configured)
- Google Maps API key placeholder
- App-wide durations (splash: 3s, animation: 300ms)

#### [route_names.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/core/constants/route_names.dart)
- All 18 route path constants for the entire app

---

### Design System

#### [app_colors.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/core/theme/app_colors.dart)
- Primary blue (`#2563EB`), Secondary purple (`#7C3AED`), Accent cyan
- Semantic colors: success/error/warning/info
- Neutral palette for backgrounds, surfaces, borders, text
- Status colors for ride lifecycle (booked/in-progress/completed/cancelled)
- Primary gradient for splash and headers

#### [app_typography.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/core/theme/app_typography.dart)
- Google Fonts **Inter** as base font
- 10 text styles: h1-h4, bodyLarge/Medium/Small, labelLarge/Medium/Small, buttonLarge/Medium, caption
- Consistent line heights and letter spacing

#### [app_spacing.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/core/theme/app_spacing.dart)
- 10 spacing tokens: xs(4) → massive(64)
- 5 border radius tokens: sm(8) → full(100)
- Screen padding constant (20)

#### [app_theme.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/core/theme/app_theme.dart)
- Complete Material 3 `ThemeData` configuration
- Styled: AppBar, ElevatedButton, OutlinedButton, TextButton, InputDecoration, Card, BottomNavigationBar, Divider, SnackBar
- All using the design system tokens

---

### Auth Feature (Clean Architecture)

#### [user_entity.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/auth/domain/entities/user_entity.dart)
- Domain entity with `Equatable` for value equality
- Fields: id, email, name, phone, avatarUrl, role, orgId, department, manager, location, platformAccess
- `fromMap` / `toMap` serialization for Supabase
- Helper getters: `isAdmin`, `hasAccess`

#### [auth_remote_datasource.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/auth/data/datasources/auth_remote_datasource.dart)
- `signUp()` — Supabase auth + profile row insert
- `signIn()` — Supabase auth + profile fetch
- `getProfile()` — Query `profiles` table by user ID
- `getCurrentUser()` — Check existing session
- `signOut()` — Clear session

#### [auth_repository.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/auth/data/repositories/auth_repository.dart)
- Thin abstraction over the data source
- Ready for adding local caching/offline support in future phases

#### [auth_provider.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/auth/presentation/providers/auth_provider.dart)
- **4 providers**: `supabaseClientProvider`, `authRemoteDataSourceProvider`, `authRepositoryProvider`, `authNotifierProvider`
- `AuthState`: user, isLoading, errorMessage with `copyWith`
- `AuthNotifier`: `checkAuthStatus()`, `signIn()`, `signUp()`, `signOut()`, `clearError()`
- Human-readable error messages for common failures

---

### Screens

#### [splash_screen.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/auth/presentation/screens/splash_screen.dart)
- Gradient background (primary → secondary)
- Animated car icon with fade + scale + elastic bounce
- App name "Carpooling" with slide-in animation
- Tagline "Ride Together, Save Together"
- Auto-checks auth session while showing animation
- Navigates to Dashboard (if authenticated) or Login (if not) after 3 seconds

#### [login_screen.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/auth/presentation/screens/login_screen.dart)
- Gradient header with branding (logo + "Welcome" + "Carpooling")
- White card form with elevation shadow
- Email/Mobile field with validation
- Password field with show/hide toggle
- Login button with loading spinner
- Error message banner for failed attempts
- "Or" divider + "Create New Account" link
- Fade + slide entrance animation

#### [signup_screen.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/auth/presentation/screens/signup_screen.dart)
- Back button to return to Login
- Avatar upload placeholder with camera icon
- 5 form fields: Name, Email, Phone, Password, Confirm Password
- All fields validated (name min 2 chars, email format, phone 10 digits, password min 6, confirm match)
- Sign Up button with loading spinner
- Error message banner
- "Already have an account? Login" link

#### [dashboard_screen.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/features/dashboard/presentation/screens/dashboard_screen.dart)
- **AppBar**: Logo with gradient background, "Carpooling" brand name, Wallet chip, Profile avatar (user's first initial)
- **Profile Menu**: Bottom sheet modal with avatar, name, email, logout button
- **Bottom Navigation**: 5 tabs (Dashboard, My Trips, History, Vehicle, Settings) with animated active indicator
- **ShellRoute child**: Renders the active tab's content
- Route-synced tab highlighting

---

## Verification Results

```
$ flutter analyze
Analyzing app...
No issues found! (ran in 9.5s)

$ flutter test
00:00 +1: All tests passed!
```

---

## What You Need Before Running

> [!IMPORTANT]
> Configure these in [app_constants.dart](file:///Users/sudhanshukumar/Desktop/car_pooling/app/lib/core/constants/app_constants.dart) before running the app:

1. **Supabase Project** — Create a project at [supabase.com](https://supabase.com), then:
   - Set `supabaseUrl` to your project URL
   - Set `supabaseAnonKey` to your project's anon/public key
   - Create a `profiles` table:
   ```sql
   CREATE TABLE profiles (
     id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
     email TEXT,
     name TEXT,
     phone TEXT,
     avatar_url TEXT,
     role TEXT DEFAULT 'employee',
     org_id UUID,
     department TEXT,
     manager TEXT,
     location TEXT,
     platform_access TEXT DEFAULT 'granted',
     created_at TIMESTAMPTZ DEFAULT NOW(),
     updated_at TIMESTAMPTZ DEFAULT NOW()
   );

   ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
   CREATE POLICY "Users can read own profile" ON profiles FOR SELECT USING (auth.uid() = id);
   CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);
   CREATE POLICY "Users can insert own profile" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
   ```

2. **Run the app**:
   ```bash
   cd /Users/sudhanshukumar/Desktop/car_pooling/app
   flutter run -d chrome   # Web
   flutter run              # Android (if emulator running)
   ```

---

## What Comes Next — Phase 2

Phase 2 (Ride Discovery & Publishing) will add:
- Dashboard home content with Find/Offer ride tab toggle
- Location input with Google Maps autocomplete
- Route Confirmation screen with interactive map
- Available Rides list with ride cards and "Book Now"
- Offer Ride form with vehicle selection + publish

All the navigation scaffolding (routes, bottom nav, shell) is already in place — Phase 2 plugs directly into the existing `dashboard` route.
