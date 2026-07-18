import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/user_entity.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/repositories/auth_repository.dart';

enum SignUpOutcome { authenticated, needsEmailConfirmation, failed }

// --- Providers ---

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSource(ref.read(supabaseClientProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(authRemoteDataSourceProvider));
});

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((
  ref,
) {
  return AuthNotifier(ref.read(authRepositoryProvider));
});

// --- State ---

class AuthState {
  final UserEntity? user;
  final bool isLoading;
  final String? errorMessage;

  const AuthState({this.user, this.isLoading = false, this.errorMessage});

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    UserEntity? user,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

// --- Notifier ---

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;

  AuthNotifier(this._repository) : super(const AuthState());

  /// Check if user has existing session on app launch
  Future<void> checkAuthStatus() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _repository.getCurrentUser();
      state = AuthState(user: user, isLoading: false);
    } catch (e) {
      state = const AuthState(isLoading: false);
    }
  }

  /// Sign in with email and password
  Future<bool> signIn({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _repository.signIn(email: email, password: password);
      state = AuthState(user: user, isLoading: false);
      return true;
    } catch (e) {
      String message = 'Login failed. Please try again.';
      final error = e.toString().toLowerCase();
      if (error.contains('invalid login credentials') ||
          error.contains('invalid_credentials')) {
        message = 'Invalid email or password.';
      } else if (error.contains('email_provider_disabled') ||
          error.contains('email logins are disabled') ||
          error.contains('email signups are disabled')) {
        message =
            'Email login is disabled in Supabase. Enable the Email provider in Authentication settings.';
      } else if (error.contains('email not confirmed')) {
        message = 'Please confirm your email before logging in.';
      } else if (error.contains('network') ||
          error.contains('socketexception') ||
          error.contains('timeout')) {
        message = 'Network error. Check your connection.';
      } else if (error.contains('profile not found') ||
          error.contains('row not found')) {
        message =
            'Your account profile is incomplete. Run the Supabase migration and try again.';
      }
      state = state.copyWith(isLoading: false, errorMessage: message);
      return false;
    }
  }

  /// Sign up with email, password, name, phone
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
    String? orgId,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await _repository.signUp(
        email: email,
        password: password,
        name: name,
        phone: phone,
        orgId: orgId,
      );
      if (result.requiresEmailConfirmation) {
        state = const AuthState(isLoading: false);
        return SignUpOutcome.needsEmailConfirmation;
      }
      state = AuthState(user: result.user, isLoading: false);
      return SignUpOutcome.authenticated;
    } catch (e) {
      String message = 'Registration failed. Please try again.';
      final error = e.toString().toLowerCase();
      if (error.contains('already registered') ||
          error.contains('already been registered') ||
          error.contains('user already exists')) {
        message = 'This email is already registered.';
      } else if (error.contains('rate limit')) {
        message = 'Too many attempts. Please wait and try again.';
      } else if (error.contains('invalid email')) {
        message = 'Enter a valid email address.';
      } else if (error.contains('email_provider_disabled') ||
          error.contains('email signups are disabled') ||
          error.contains('signups not allowed')) {
        message =
            'Email sign-up is disabled in Supabase. Enable the Email provider in Authentication settings.';
      } else if (error.contains('database error saving new user')) {
        message =
            'Supabase could not create the profile. Run schema.sql in the Supabase SQL editor and try again.';
      }
      state = state.copyWith(isLoading: false, errorMessage: message);
      return SignUpOutcome.failed;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _repository.signOut();
    state = const AuthState();
  }

  /// Clear any error message
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}
