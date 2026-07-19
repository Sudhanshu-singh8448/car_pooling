import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/user_entity.dart';

class SignUpResult {
  final UserEntity? user;
  final bool requiresEmailConfirmation;

  const SignUpResult({this.user, this.requiresEmailConfirmation = false});
}

class AuthRemoteDataSource {
  final SupabaseClient _client;

  AuthRemoteDataSource(this._client);

  /// Sign up with email + password.
  ///
  /// The profile is created by the Supabase `auth.users` trigger. This is
  /// important when email confirmation is enabled because there is no
  /// authenticated client session available for a profile insert yet.
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
    String? orgId,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final response = await _client.auth.signUp(
      email: normalizedEmail,
      password: password,
      data: {
        'name': name,
        'phone': phone,
        if (orgId != null && orgId.isNotEmpty) 'org_id': orgId,
      },
    );

    final userId = response.user?.id;
    if (userId == null) {
      throw Exception('Sign up failed: no user returned');
    }

    // The Supabase database has a trigger (handle_new_user) that automatically
    // creates the profile row upon signup. We don't need to manually upsert
    // here, which would fail due to RLS if email confirmations are enabled
    // (since the user isn't logged in yet).

    if (response.session == null) {
      // This also supports a Supabase project whose email-confirmation
      // setting was just changed and has not produced a session yet.
      try {
        final signInResponse = await _client.auth.signInWithPassword(
          email: normalizedEmail,
          password: password,
        );
        if (signInResponse.user != null) {
          return SignUpResult(
            user: await _profileOrFallback(
              signInResponse.user!,
              name: name,
              phone: phone,
            ),
          );
        }
      } on AuthException catch (error) {
        if (error.code != 'email_not_confirmed') rethrow;
      }
      return const SignUpResult(requiresEmailConfirmation: true);
    }

    // If we have a session, the user is logged in. We can safely query their
    // profile (which the trigger created).
    return SignUpResult(
      user: await _profileOrFallback(response.user!, name: name, phone: phone),
    );
  }

  Future<UserEntity> _profileOrFallback(
    User authUser, {
    required String name,
    required String phone,
  }) async {
    try {
      return await getProfile(authUser.id);
    } catch (_) {
      // Keep the user authenticated while an existing Supabase trigger or
      // profile migration is being applied.
      return UserEntity(
        id: authUser.id,
        email: authUser.email ?? '',
        name: name,
        phone: phone,
      );
    }
  }

  /// Sign in with the email and password used during registration.
  Future<UserEntity> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );

    final userId = response.user?.id;
    if (userId == null) {
      throw Exception('Login failed: invalid credentials');
    }

    return await _profileOrFallback(
      response.user!,
      name: response.user!.userMetadata?['name'] as String? ?? '',
      phone: response.user!.userMetadata?['phone'] as String? ?? '',
    );
  }

  /// Fetch a profile, repairing accounts created before the profile trigger
  /// was installed.
  Future<UserEntity> getProfile(String userId) async {
    final data = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (data != null) return UserEntity.fromMap(data);

    final authUser = _client.auth.currentUser;
    if (authUser == null || authUser.id != userId) {
      throw Exception('Profile not found for authenticated user');
    }

    final metadata = authUser.userMetadata ?? const <String, dynamic>{};
    final profileData = {
      'id': authUser.id,
      'email': authUser.email ?? '',
      'name': metadata['name'] as String? ?? '',
      'phone': metadata['phone'] as String? ?? '',
      'role': 'employee',
      'platform_access': 'granted',
    };
    return UserEntity.fromMap(profileData);
  }

  /// Get current session user, if any
  Future<UserEntity?> getCurrentUser() async {
    final session = _client.auth.currentSession;
    if (session == null) return null;

    final userId = session.user.id;
    try {
      return await getProfile(userId).timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  /// Update the editable profile fields and keep Supabase Auth metadata in
  /// sync with the profile row.
  Future<UserEntity> updateProfile({
    required UserEntity currentUser,
    required String name,
    required String email,
    required String phone,
    String? department,
    String? manager,
    String? location,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final authUser = _client.auth.currentUser;
    if (authUser == null || authUser.id != currentUser.id) {
      throw Exception('Not authenticated');
    }

    final emailChanged = normalizedEmail != (authUser.email ?? '').toLowerCase();
    await _client.auth.updateUser(
      UserAttributes(
        email: emailChanged ? normalizedEmail : null,
        data: {
          'name': name.trim(),
          'phone': phone.trim(),
        },
      ),
    );

    final data = await _client
        .from('profiles')
        .update({
          'name': name.trim(),
          'email': normalizedEmail,
          'phone': phone.trim(),
          'department': _nullableValue(department),
          'manager': _nullableValue(manager),
          'location': _nullableValue(location),
        })
        .eq('id', currentUser.id)
        .select()
        .single();

    return UserEntity.fromMap(data);
  }

  String? _nullableValue(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Sign out
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Check if there's an active session
  bool get hasSession => _client.auth.currentSession != null;
}
