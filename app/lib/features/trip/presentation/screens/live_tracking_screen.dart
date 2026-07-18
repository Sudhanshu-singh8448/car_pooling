import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/maps_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/trip_entity.dart';
import '../providers/trip_provider.dart';

/// Screen 12 — live trip tracking.
/// Driver: broadcasts GPS via Supabase (inserts into ride_locations).
/// Passenger: subscribes to realtime inserts and follows the vehicle.
class LiveTrackingScreen extends ConsumerStatefulWidget {
  final TripEntity trip;
  const LiveTrackingScreen({super.key, required this.trip});

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  GoogleMapController? _mapController;
  RealtimeChannel? _channel;
  StreamSubscription<Position>? _positionSub;

  LatLng? _vehiclePosition;
  double? _speedKmh;
  int? _etaMinutes;
  String? _statusMessage;
  bool _isBroadcasting = false;

  TripEntity get trip => widget.trip;

  @override
  void initState() {
    super.initState();
    if (trip.isDriver) {
      _startBroadcasting();
    } else {
      _startListening();
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    if (_channel != null) {
      ref.read(tripRepositoryProvider).unsubscribe(_channel!);
    }
    super.dispose();
  }

  // ---------- Driver: broadcast GPS ----------

  Future<void> _startBroadcasting() async {
    setState(() => _statusMessage = 'Acquiring GPS...');
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(
          () => _statusMessage =
              'Location permission denied. Enable it to share your position.',
        );
        return;
      }

      _positionSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          ).listen(
            (position) {
              _onDriverPosition(position);
            },
            onError: (_) {
              if (mounted) {
                setState(() => _statusMessage = 'GPS signal lost. Retrying...');
              }
            },
          );
      setState(() {
        _isBroadcasting = true;
        _statusMessage = 'Sharing live location with passengers';
      });
    } catch (_) {
      setState(() => _statusMessage = 'Could not access GPS.');
    }
  }

  DateTime _lastPublish = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _onDriverPosition(Position position) async {
    final latLng = LatLng(position.latitude, position.longitude);
    _updateVehicle(latLng, speedMs: position.speed);
    // Throttle inserts to every ~4 seconds
    if (DateTime.now().difference(_lastPublish).inSeconds >= 4) {
      _lastPublish = DateTime.now();
      try {
        await ref
            .read(tripRepositoryProvider)
            .publishLocation(
              rideId: trip.ride.id,
              latitude: position.latitude,
              longitude: position.longitude,
              speed: position.speed,
              heading: position.heading,
            );
      } catch (_) {
        // Ignore transient failures; next tick retries.
      }
    }
  }

  // ---------- Passenger: subscribe ----------

  Future<void> _startListening() async {
    setState(() => _statusMessage = 'Waiting for driver location...');
    // Show last known position immediately if available
    final last = await ref
        .read(tripRepositoryProvider)
        .getLastLocation(trip.ride.id);
    if (last != null && mounted) {
      _updateVehicle(
        LatLng(
          (last['latitude'] as num).toDouble(),
          (last['longitude'] as num).toDouble(),
        ),
        speedMs: (last['speed'] as num?)?.toDouble(),
      );
    }
    _channel = ref.read(tripRepositoryProvider).subscribeToLocations(
      trip.ride.id,
      (location) {
        if (!mounted) return;
        _updateVehicle(
          LatLng(
            (location['latitude'] as num).toDouble(),
            (location['longitude'] as num).toDouble(),
          ),
          speedMs: (location['speed'] as num?)?.toDouble(),
        );
      },
    );
  }

  void _updateVehicle(LatLng position, {double? speedMs}) {
    final destination = LatLng(
      trip.ride.destination.lat,
      trip.ride.destination.lng,
    );
    final remainingKm =
        MapsService.haversineKm(
          position.latitude,
          position.longitude,
          destination.latitude,
          destination.longitude,
        ) *
        1.3; // road factor
    final speedKmh = (speedMs != null && speedMs > 1) ? speedMs * 3.6 : 30.0;
    setState(() {
      _vehiclePosition = position;
      _speedKmh = speedMs != null ? speedMs * 3.6 : null;
      _etaMinutes = (remainingKm / speedKmh * 60).round().clamp(1, 999);
      if (!trip.isDriver) _statusMessage = null;
    });
    _mapController?.animateCamera(CameraUpdate.newLatLng(position));
  }

  @override
  Widget build(BuildContext context) {
    final ride = trip.ride;
    final pickup = LatLng(ride.pickup.lat, ride.pickup.lng);
    final destination = LatLng(ride.destination.lat, ride.destination.lng);
    final routePoints = ride.routePolyline != null
        ? MapsService.decodePolyline(ride.routePolyline!)
        : <LatLng>[pickup, destination];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Ride'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // Route header
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            color: AppColors.surface,
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.trip_origin,
                      size: 16,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        ride.pickup.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 16,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        ride.destination.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: pickup,
                    zoom: 13,
                  ),
                  onMapCreated: (c) => _mapController = c,
                  markers: {
                    Marker(
                      markerId: const MarkerId('pickup'),
                      position: pickup,
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueGreen,
                      ),
                    ),
                    Marker(
                      markerId: const MarkerId('destination'),
                      position: destination,
                    ),
                    if (_vehiclePosition != null)
                      Marker(
                        markerId: const MarkerId('vehicle'),
                        position: _vehiclePosition!,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueAzure,
                        ),
                        infoWindow: InfoWindow(title: ride.vehicleModel),
                      ),
                  },
                  polylines: {
                    if (routePoints.isNotEmpty)
                      Polyline(
                        polylineId: const PolylineId('route'),
                        points: routePoints,
                        color: AppColors.primary,
                        width: 5,
                      ),
                  },
                  myLocationEnabled: trip.isDriver,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                ),
                if (_statusMessage != null)
                  Positioned(
                    top: AppSpacing.lg,
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: _isBroadcasting
                            ? AppColors.success.withValues(alpha: 0.95)
                            : AppColors.warning.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isBroadcasting
                                ? Icons.gps_fixed
                                : Icons.info_outline,
                            size: 18,
                            color: AppColors.white,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ETA panel
          Container(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.directions_car,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _etaMinutes != null
                              ? 'Arriving in ~$_etaMinutes minutes'
                              : 'Waiting for location...',
                          style: AppTypography.labelLarge,
                        ),
                        if (_speedKmh != null)
                          Text(
                            '${_speedKmh!.toStringAsFixed(0)} km/h',
                            style: AppTypography.caption,
                          ),
                      ],
                    ),
                  ),
                  Text(
                    ride.vehicleRegistration,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
