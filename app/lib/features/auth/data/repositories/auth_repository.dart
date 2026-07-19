import '../../domain/entities/user_entity.dart';
import '../datasources/auth_remote_datasource.dart';

class AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;

  AuthRepository(this._remoteDataSource);

  Future<SignUpResult> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
    String? orgId,
  }) {
    return _remoteDataSource.signUp(
      email: email,
      password: password,
      name: name,
      phone: phone,
      orgId: orgId,
    );
  }

  Future<UserEntity> signIn({required String email, required String password}) {
    return _remoteDataSource.signIn(email: email, password: password);
  }

  Future<UserEntity?> getCurrentUser() {
    return _remoteDataSource.getCurrentUser();
  }

  Future<UserEntity> updateProfile({
    required UserEntity currentUser,
    required String name,
    required String email,
    required String phone,
    String? department,
    String? manager,
    String? location,
  }) {
    return _remoteDataSource.updateProfile(
      currentUser: currentUser,
      name: name,
      email: email,
      phone: phone,
      department: department,
      manager: manager,
      location: location,
    );
  }

  Future<void> signOut() {
    return _remoteDataSource.signOut();
  }

  bool get hasSession => _remoteDataSource.hasSession;
}
