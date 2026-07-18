import 'package:equatable/equatable.dart';

import 'ride_entity.dart';

/// A ride returned from search, enriched with how well it matches the
/// passenger's requested pickup/destination along the driver's route.
class RideMatch extends Equatable {
  final RideEntity ride;

  /// Straight-line walking distance (metres) from the passenger's pickup
  /// to the nearest point on the driver's route.
  final double walkToPickupMeters;

  /// Walking distance (metres) from the nearest route point to the
  /// passenger's destination.
  final double walkFromDropMeters;

  /// Estimated time the driver reaches the passenger's boarding point.
  final DateTime pickupEta;

  /// True when the boarding point is along the route rather than at the
  /// driver's own starting point.
  final bool isMidwayPickup;

  /// Latitude/longitude of the suggested boarding point on the route.
  final double boardingLat;
  final double boardingLng;

  const RideMatch({
    required this.ride,
    required this.walkToPickupMeters,
    required this.walkFromDropMeters,
    required this.pickupEta,
    required this.isMidwayPickup,
    required this.boardingLat,
    required this.boardingLng,
  });

  /// Human-friendly walk label, e.g. "80 m walk" or "1.2 km walk".
  String get walkLabel {
    if (walkToPickupMeters < 1000) {
      return '${walkToPickupMeters.round()} m walk';
    }
    return '${(walkToPickupMeters / 1000).toStringAsFixed(1)} km walk';
  }

  @override
  List<Object?> get props => [ride, walkToPickupMeters, pickupEta];
}
