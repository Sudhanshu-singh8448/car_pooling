import 'package:equatable/equatable.dart';

/// A geographic point with a human-readable address.
class LocationPoint extends Equatable {
  final String address;
  final double lat;
  final double lng;

  const LocationPoint({
    required this.address,
    required this.lat,
    required this.lng,
  });

  @override
  List<Object?> get props => [address, lat, lng];

  @override
  String toString() => address;
}
