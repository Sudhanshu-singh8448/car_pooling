import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/user_entity.dart';

class AuthRemoteDataSource {
  final SupabaseClient _client;

  AuthRemoteDataSource(this._client);

  /// Sign up with email + password, then insert profile row
  Future<UserEntity> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'name': name, 'phone': phone},
    );

    final userId = response.user?.id;
    if (userId == null) {
      throw Exception('Sign up failed: no user returned');
    }

    // Insert profile into 'profiles' table
    final profileData = {
      'id': userId,
      'email': email,
      'name': name,
      'phone': phone,
      'role': 'employee',
      'platform_access': 'granted',
    };

    await _client.from('profiles').upsert(profileData);

    return UserEntity.fromMap(profileData);
  }

  /// Sign in with email + password
  Future<UserEntity> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final userId = response.user?.id;
    if (userId == null) {
      throw Exception('Login failed: invalid credentials');
    }

    return await getProfile(userId);
  }

  /// Fetch profile from 'profiles' table
  Future<UserEntity> getProfile(String userId) async {
    final data = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();

    return UserEntity.fromMap(data);
  }

  /// Get current session user, if any
  Future<UserEntity?> getCurrentUser() async {
    final session = _client.auth.currentSession;
    if (session == null) return null;

    final userId = session.user.id;
    try {
      return await getProfile(userId);
    } catch (_) {
      return null;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Check if there's an active session
  bool get hasSession => _client.auth.currentSession != null;
}
