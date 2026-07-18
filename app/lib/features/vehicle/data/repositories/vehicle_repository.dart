import '../datasources/vehicle_remote_datasource.dart';
import '../../domain/entities/vehicle_entity.dart';

class VehicleRepository {
  final VehicleRemoteDataSource _dataSource;

  VehicleRepository(this._dataSource);

  Future<List<VehicleEntity>> getMyVehicles() => _dataSource.getMyVehicles();

  Future<VehicleEntity> addVehicle({
    required String model,
    required String registrationNumber,
    required int seatingCapacity,
  }) => _dataSource.addVehicle(
    model: model,
    registrationNumber: registrationNumber,
    seatingCapacity: seatingCapacity,
  );

  Future<VehicleEntity> updateVehicle({
    required String id,
    String? model,
    int? seatingCapacity,
    String? status,
  }) => _dataSource.updateVehicle(
    id: id,
    model: model,
    seatingCapacity: seatingCapacity,
    status: status,
  );

  Future<void> deleteVehicle(String id) => _dataSource.deleteVehicle(id);
}
