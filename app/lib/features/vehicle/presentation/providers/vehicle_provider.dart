import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/vehicle_remote_datasource.dart';
import '../../data/repositories/vehicle_repository.dart';
import '../../domain/entities/vehicle_entity.dart';

final vehicleRemoteDataSourceProvider = Provider<VehicleRemoteDataSource>((
  ref,
) {
  return VehicleRemoteDataSource(ref.read(supabaseClientProvider));
});

final vehicleRepositoryProvider = Provider<VehicleRepository>((ref) {
  return VehicleRepository(ref.read(vehicleRemoteDataSourceProvider));
});

/// The current user's vehicles. Invalidate after add/edit/delete.
final myVehiclesProvider = FutureProvider<List<VehicleEntity>>((ref) async {
  return ref.read(vehicleRepositoryProvider).getMyVehicles();
});
