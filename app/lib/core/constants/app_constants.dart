import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Global app configuration.
///
/// All secrets (Supabase / Google Maps / Razorpay keys) are loaded from the
/// bundled `.env` file at startup via `flutter_dotenv`. The `.env` file is
/// git-ignored — commit only `.env.example` as a template.
///
/// Call `await dotenv.load(fileName: '.env')` in `main()` before touching
/// any of the getters below.
class AppConstants {
  AppConstants._();

  static const String appName = 'Carpooling';
  static const String appTagline = 'Ride Together, Save Together';

  // ── Secrets (read from .env) ──────────────────────────────────────────────
  static String get supabaseUrl => _required('SUPABASE_URL');
  static String get supabaseAnonKey => _required('SUPABASE_ANON_KEY');
  static String get googleMapsApiKey => _required('GOOGLE_MAPS_API_KEY');
  static String get razorpayKeyId => _required('RAZORPAY_KEY_ID');

  static String _required(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StateError(
        'Missing "$key" in .env. Copy .env.example to .env and fill in real '
        'values, then hot-restart the app.',
      );
    }
    return value;
  }

  // ── Non-secret constants ──────────────────────────────────────────────────
  static const Duration splashDuration = Duration(seconds: 3);
  static const Duration animationDuration = Duration(milliseconds: 300);
  static const Duration snackBarDuration = Duration(seconds: 3);

  static const int pageSize = 20;
}
