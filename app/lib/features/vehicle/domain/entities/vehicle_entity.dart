import 'package:equatable/equatable.dart';

class VehicleEntity extends Equatable {
  final String id;
  final String ownerId;
  final String model;
  final String registrationNumber;
  final int seatingCapacity;
  final String status; // active | inactive

  const VehicleEntity({
    required this.id,
    required this.ownerId,
    required this.model,
    required this.registrationNumber,
    required this.seatingCapacity,
    this.status = 'active',
  });

  bool get isActive => status == 'active';

  factory VehicleEntity.fromMap(Map<String, dynamic> map) {
    return VehicleEntity(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      model: map['model'] as String,
      registrationNumber: map['registration_number'] as String,
      seatingCapacity: (map['seating_capacity'] as num).toInt(),
      status: map['status'] as String? ?? 'active',
    );
  }

  @override
  List<Object?> get props => [id, model, registrationNumber, status];
}
