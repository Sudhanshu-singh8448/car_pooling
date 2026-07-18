import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/route_names.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: RouteNames.splash,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final isLoggedIn = authState.user != null;
      final isAuthRoute = state.matchedLocation == RouteNames.login ||
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
      ShellRoute(
        builder: (context, state, child) => DashboardScreen(child: child),
        routes: [
          GoRoute(
            path: RouteNames.dashboard,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: _DashboardHome(),
            ),
          ),
          GoRoute(
            path: RouteNames.myTrips,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: _PlaceholderScreen(title: 'My Trips'),
            ),
          ),
          GoRoute(
            path: RouteNames.rideHistory,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: _PlaceholderScreen(title: 'Ride History'),
            ),
          ),
          GoRoute(
            path: RouteNames.myVehicle,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: _PlaceholderScreen(title: 'My Vehicle'),
            ),
          ),
          GoRoute(
            path: RouteNames.settings,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: _PlaceholderScreen(title: 'Settings'),
            ),
          ),
        ],
      ),
    ],
  );
});

/// The main dashboard home content (Find/Offer ride tabs)
class _DashboardHome extends StatelessWidget {
  const _DashboardHome();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Dashboard — Find & Offer Rides\n(Phase 2)'),
    );
  }
}

/// Placeholder used for tabs that will be built in later phases
class _PlaceholderScreen extends StatelessWidget {
  final String title;
  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '$title\n(Coming in next phase)',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
