import '../datasources/ride_remote_datasource.dart';
import '../../domain/entities/booking_entity.dart';
import '../../domain/entities/location_point.dart';
import '../../domain/entities/ride_entity.dart';

class RideRepository {
  final RideRemoteDataSource _dataSource;

  RideRepository(this._dataSource);

  Future<RideEntity> publishRide({
    required String vehicleId,
    required LocationPoint pickup,
    required LocationPoint destination,
    required DateTime departureTime,
    required int totalSeats,
    required double farePerSeat,
    String? routePolyline,
    double? distanceKm,
    int? durationMinutes,
    bool isRecurring = false,
    String? recurringDays,
  }) => _dataSource.publishRide(
    vehicleId: vehicleId,
    pickup: pickup,
    destination: destination,
    departureTime: departureTime,
    totalSeats: totalSeats,
    farePerSeat: farePerSeat,
    routePolyline: routePolyline,
    distanceKm: distanceKm,
    durationMinutes: durationMinutes,
    isRecurring: isRecurring,
    recurringDays: recurringDays,
  );

  Future<List<RideEntity>> searchRides({
    required LocationPoint pickup,
    required LocationPoint destination,
    required DateTime date,
    required int seats,
    double radiusKm = 5,
  }) => _dataSource.searchRides(
    pickup: pickup,
    destination: destination,
    date: date,
    seats: seats,
    radiusKm: radiusKm,
  );

  Future<BookingEntity> bookRide({
    required String rideId,
    required int seats,
  }) => _dataSource.bookRide(rideId: rideId, seats: seats);
}
