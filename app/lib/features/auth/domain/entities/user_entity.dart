import 'package:equatable/equatable.dart';

class UserEntity extends Equatable {
  final String id;
  final String email;
  final String name;
  final String phone;
  final String? avatarUrl;
  final String role; // 'admin' | 'employee'
  final String? orgId;
  final String? department;
  final String? manager;
  final String? location;
  final String platformAccess; // 'granted' | 'revoked'

  const UserEntity({
    required this.id,
    required this.email,
    required this.name,
    required this.phone,
    this.avatarUrl,
    this.role = 'employee',
    this.orgId,
    this.department,
    this.manager,
    this.location,
    this.platformAccess = 'granted',
  });

  bool get isAdmin => role == 'admin';
  bool get hasAccess => platformAccess == 'granted';

  UserEntity copyWith({
    String? id,
    String? email,
    String? name,
    String? phone,
    String? avatarUrl,
    String? role,
    String? orgId,
    String? department,
    String? manager,
    String? location,
    String? platformAccess,
  }) {
    return UserEntity(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      orgId: orgId ?? this.orgId,
      department: department ?? this.department,
      manager: manager ?? this.manager,
      location: location ?? this.location,
      platformAccess: platformAccess ?? this.platformAccess,
    );
  }

  factory UserEntity.fromMap(Map<String, dynamic> map) {
    return UserEntity(
      id: map['id'] as String,
      email: map['email'] as String? ?? '',
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      avatarUrl: map['avatar_url'] as String?,
      role: map['role'] as String? ?? 'employee',
      orgId: map['org_id'] as String?,
      department: map['department'] as String?,
      manager: map['manager'] as String?,
      location: map['location'] as String?,
      platformAccess: map['platform_access'] as String? ?? 'granted',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'phone': phone,
      'avatar_url': avatarUrl,
      'role': role,
      'org_id': orgId,
      'department': department,
      'manager': manager,
      'location': location,
      'platform_access': platformAccess,
    };
  }

  @override
  List<Object?> get props => [id, email, name, phone, role, orgId, platformAccess];
}
