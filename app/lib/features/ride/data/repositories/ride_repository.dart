import '../../../../core/services/maps_service.dart';
import '../datasources/ride_remote_datasource.dart';
import '../../domain/entities/booking_entity.dart';
import '../../domain/entities/location_point.dart';
import '../../domain/entities/ride_entity.dart';
import '../../domain/entities/ride_match.dart';

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

  Future<List<RideMatch>> searchRides({
    required LocationPoint pickup,
    required LocationPoint destination,
    required DateTime date,
    required int seats,
    double radiusKm = 5,

    /// Max walking distance (km) from the passenger's points to the
    /// driver's route for a ride to count as "on the way".
    double corridorKm = 2.0,
  }) async {
    final rides = await _dataSource.searchRides(
      pickup: pickup,
      destination: destination,
      date: date,
      seats: seats,
      radiusKm: radiusKm,
    );
    final matches = rides
        .map((r) => _matchRide(r, pickup, destination, corridorKm))
        .whereType<RideMatch>()
        .toList();
    // Closest walk first, then earliest boarding time.
    matches.sort((a, b) {
      final walk = a.walkToPickupMeters.compareTo(b.walkToPickupMeters);
      return walk != 0 ? walk : a.pickupEta.compareTo(b.pickupEta);
    });
    return matches;
  }

  /// Decides whether [ride] passes near the passenger's pickup AND
  /// destination (in the right direction), and computes the boarding
  /// point, walking distance and driver-arrival ETA.
  RideMatch? _matchRide(
    RideEntity ride,
    LocationPoint pickup,
    LocationPoint destination,
    double corridorKm,
  ) {
    final points = MapsService.decodePolyline(ride.routePolyline ?? '');

    if (points.length < 2) {
      // No route stored — endpoint-to-endpoint match (legacy behaviour).
      final pickupKm = MapsService.haversineKm(
        pickup.lat,
        pickup.lng,
        ride.pickup.lat,
        ride.pickup.lng,
      );
      final dropKm = MapsService.haversineKm(
        destination.lat,
        destination.lng,
        ride.destination.lat,
        ride.destination.lng,
      );
      if (pickupKm > corridorKm || dropKm > corridorKm) return null;
      return RideMatch(
        ride: ride,
        walkToPickupMeters: pickupKm * 1000,
        walkFromDropMeters: dropKm * 1000,
        pickupEta: ride.departureTime,
        isMidwayPickup: false,
        boardingLat: ride.pickup.lat,
        boardingLng: ride.pickup.lng,
      );
    }

    // Nearest route point to the passenger's pickup and destination.
    var pickupIdx = 0, dropIdx = 0;
    var pickupKm = double.infinity, dropKm = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final dPickup = MapsService.haversineKm(
        pickup.lat,
        pickup.lng,
        p.latitude,
        p.longitude,
      );
      if (dPickup < pickupKm) {
        pickupKm = dPickup;
        pickupIdx = i;
      }
      final dDrop = MapsService.haversineKm(
        destination.lat,
        destination.lng,
        p.latitude,
        p.longitude,
      );
      if (dDrop < dropKm) {
        dropKm = dDrop;
        dropIdx = i;
      }
    }

    // Must be within walking distance of the route, and the pickup must
    // come BEFORE the drop along the driver's direction of travel.
    if (pickupKm > corridorKm || dropKm > corridorKm) return null;
    if (pickupIdx >= dropIdx) return null;

    // Distance along the route up to the boarding point → driver ETA.
    var kmToBoarding = 0.0, totalKm = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      final seg = MapsService.haversineKm(
        points[i].latitude,
        points[i].longitude,
        points[i + 1].latitude,
        points[i + 1].longitude,
      );
      totalKm += seg;
      if (i < pickupIdx) kmToBoarding += seg;
    }
    final durationMin = ride.durationMinutes ?? (totalKm / 35 * 60).round();
    final minutesToBoarding = totalKm <= 0
        ? 0
        : (durationMin * (kmToBoarding / totalKm)).round();

    return RideMatch(
      ride: ride,
      walkToPickupMeters: pickupKm * 1000,
      walkFromDropMeters: dropKm * 1000,
      pickupEta: ride.departureTime.add(Duration(minutes: minutesToBoarding)),
      isMidwayPickup: kmToBoarding > 0.3,
      boardingLat: points[pickupIdx].latitude,
      boardingLng: points[pickupIdx].longitude,
    );
  }

  Future<BookingEntity> bookRide({
    required String rideId,
    required int seats,
  }) => _dataSource.bookRide(rideId: rideId, seats: seats);
}
