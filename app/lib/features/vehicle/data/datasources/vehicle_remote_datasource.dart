import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/vehicle_entity.dart';

class VehicleRemoteDataSource {
  final SupabaseClient _client;

  VehicleRemoteDataSource(this._client);

  Future<List<VehicleEntity>> getMyVehicles() async {
    final userId = _client.auth.currentUser!.id;
    final data = await _client
        .from('vehicles')
        .select()
        .eq('owner_id', userId)
        .eq('is_deleted', false)
        .order('created_at');
    return (data as List)
        .map((v) => VehicleEntity.fromMap(v as Map<String, dynamic>))
        .toList();
  }

  Future<VehicleEntity> addVehicle({
    required String model,
    required String registrationNumber,
    required int seatingCapacity,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final data = await _client
        .from('vehicles')
        .insert({
          'owner_id': userId,
          'model': model,
          'registration_number': registrationNumber.toUpperCase(),
          'seating_capacity': seatingCapacity,
        })
        .select()
        .single();
    return VehicleEntity.fromMap(data);
  }

  Future<VehicleEntity> updateVehicle({
    required String id,
    String? model,
    int? seatingCapacity,
    String? status,
  }) async {
    final data = await _client
        .from('vehicles')
        .update({
          'model': ?model,
          'seating_capacity': ?seatingCapacity,
          'status': ?status,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();
    return VehicleEntity.fromMap(data);
  }

  Future<void> deleteVehicle(String id) async {
    await _client.from('vehicles').update({'is_deleted': true}).eq('id', id);
  }
}
