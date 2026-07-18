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
  }) {
    return _remoteDataSource.signUp(
      email: email,
      password: password,
      name: name,
      phone: phone,
    );
  }

  Future<UserEntity> signIn({required String email, required String password}) {
    return _remoteDataSource.signIn(email: email, password: password);
  }

  Future<UserEntity?> getCurrentUser() {
    return _remoteDataSource.getCurrentUser();
  }

  Future<void> signOut() {
    return _remoteDataSource.signOut();
  }

  bool get hasSession => _remoteDataSource.hasSession;
}
