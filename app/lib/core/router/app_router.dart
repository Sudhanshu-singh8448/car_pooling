import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/route_names.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/admin/presentation/screens/admin_dashboard_screen.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/feedback/presentation/screens/feedback_screen.dart';
import '../../features/history/presentation/screens/ride_history_screen.dart';
import '../../features/notification/presentation/screens/notification_center_screen.dart';
import '../../features/payment/presentation/screens/payment_method_screen.dart';
import '../../features/payment/presentation/screens/wallet_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/ride/presentation/screens/dashboard_home_screen.dart';
import '../../features/ride/presentation/screens/route_confirmation_screen.dart';
import '../../features/ride/presentation/screens/available_rides_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/profile_screen.dart';
import '../../features/trip/domain/entities/trip_entity.dart';
import '../../features/trip/presentation/screens/live_tracking_screen.dart';
import '../../features/trip/presentation/screens/my_trips_screen.dart';
import '../../features/trip/presentation/screens/trip_details_screen.dart';
import '../../features/trip/presentation/screens/trip_finish_screen.dart';
import '../../features/vehicle/presentation/screens/my_vehicles_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: RouteNames.splash,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      // Read auth state inside redirect (not watch) to avoid recreating the router
      final authState = ref.read(authNotifierProvider);
      final isLoggedIn = authState.user != null;
      final isAuthRoute =
          state.matchedLocation == RouteNames.login ||
          state.matchedLocation == RouteNames.signUp;
      final isSplash = state.matchedLocation == RouteNames.splash;

      // Don't redirect from splash — it handles its own navigation
      if (isSplash) return null;

      // If not logged in and not on auth route, go to login
      if (!isLoggedIn && !isAuthRoute) return RouteNames.login;

      // If logged in and on auth route, go to dashboard
      if (isLoggedIn && isAuthRoute) return RouteNames.dashboard;

      return null;
    },
    routes: [
      GoRoute(
        path: RouteNames.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RouteNames.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RouteNames.signUp,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: RouteNames.routeConfirmation,
        builder: (context, state) => const RouteConfirmationScreen(),
      ),
      GoRoute(
        path: RouteNames.availableRides,
        builder: (context, state) => const AvailableRidesScreen(),
      ),
      GoRoute(
        path: RouteNames.tripDetails,
        builder: (context, state) =>
            TripDetailsScreen(trip: state.extra! as TripEntity),
      ),
      GoRoute(
        path: RouteNames.liveTracking,
        builder: (context, state) =>
            LiveTrackingScreen(trip: state.extra! as TripEntity),
      ),
      GoRoute(
        path: RouteNames.tripFinish,
        builder: (context, state) =>
            TripFinishScreen(trip: state.extra! as TripEntity),
      ),
      GoRoute(
        path: RouteNames.paymentMethod,
        builder: (context, state) =>
            PaymentMethodScreen(trip: state.extra! as TripEntity),
      ),
      GoRoute(
        path: RouteNames.chat,
        builder: (context, state) => ChatScreen(args: state.extra! as ChatArgs),
      ),
      GoRoute(
        path: RouteNames.wallet,
        builder: (context, state) => const WalletScreen(),
      ),
      GoRoute(
        path: RouteNames.reports,
        builder: (context, state) => const ReportsScreen(),
      ),
      GoRoute(
        path: RouteNames.adminDashboard,
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: RouteNames.notifications,
        builder: (context, state) => const NotificationCenterScreen(),
      ),
      GoRoute(
        path: RouteNames.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: RouteNames.feedback,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>;
          return FeedbackScreen(
            rideId: args['ride_id'] as String,
            bookingId: args['booking_id'] as String,
            revieweeId: args['reviewee_id'] as String,
            revieweeName: args['reviewee_name'] as String? ?? 'User',
          );
        },
      ),
      ShellRoute(
        builder: (context, state, child) => DashboardScreen(child: child),
        routes: [
          GoRoute(
            path: RouteNames.dashboard,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: DashboardHomeScreen()),
          ),
          GoRoute(
            path: RouteNames.myTrips,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: MyTripsScreen()),
          ),
          GoRoute(
            path: RouteNames.rideHistory,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: RideHistoryScreen()),
          ),
          GoRoute(
            path: RouteNames.myVehicle,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: MyVehiclesScreen()),
          ),
          GoRoute(
            path: RouteNames.settings,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
    ],
  );
});
