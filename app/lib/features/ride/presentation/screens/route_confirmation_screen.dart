import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/services/maps_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../vehicle/presentation/providers/vehicle_provider.dart';
import '../providers/ride_provider.dart';

/// Screen 6 — verify the calculated route before searching/publishing.
class RouteConfirmationScreen extends ConsumerStatefulWidget {
  const RouteConfirmationScreen({super.key});

  @override
  ConsumerState<RouteConfirmationScreen> createState() =>
      _RouteConfirmationScreenState();
}

class _RouteConfirmationScreenState
    extends ConsumerState<RouteConfirmationScreen> {
  GoogleMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(rideFormProvider);
    final publishState = ref.watch(publishProvider);

    if (form.pickup == null || form.destination == null) {
      // Shouldn't happen; guard anyway.
      return const Scaffold(body: Center(child: Text('Missing route data')));
    }

    final routeAsync = ref.watch(
      routeProvider((origin: form.pickup!, destination: form.destination!)),
    );
    final isOffer = form.mode == RideMode.offer;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: routeAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: AppSpacing.lg),
              Text('Calculating route...'),
            ],
          ),
        ),
        error: (_, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: AppSpacing.lg),
              const Text('Could not calculate route'),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: () => ref.invalidate(routeProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (route) => Column(
          children: [
            _buildRouteHeader(form, route),
            Expanded(child: _buildMap(form, route)),
            _buildBottomPanel(form, route, isOffer, publishState),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteHeader(RideFormState form, RouteResult route) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      color: AppColors.surface,
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.trip_origin, size: 16, color: AppColors.success),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  form.pickup!.address,
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
              const Icon(Icons.location_on, size: 16, color: AppColors.error),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  form.destination!.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _chip(Icons.route, '${route.distanceKm.toStringAsFixed(1)} km'),
              _chip(Icons.schedule, '${route.durationMinutes} min'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(RideFormState form, RouteResult route) {
    final pickup = LatLng(form.pickup!.lat, form.pickup!.lng);
    final destination = LatLng(form.destination!.lat, form.destination!.lng);
    final bounds = _boundsFor([pickup, destination, ...route.points]);

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: pickup, zoom: 12),
      onMapCreated: (controller) {
        _mapController = controller;
        Future.delayed(const Duration(milliseconds: 300), () {
          _mapController?.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 60),
          );
        });
      },
      markers: {
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Pickup'),
        ),
        Marker(
          markerId: const MarkerId('destination'),
          position: destination,
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      },
      polylines: {
        if (route.points.isNotEmpty)
          Polyline(
            polylineId: const PolylineId('route'),
            points: route.points,
            color: AppColors.primary,
            width: 5,
          ),
      },
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
    );
  }

  static LatLngBounds _boundsFor(List<LatLng> points) {
    var minLat = points.first.latitude, maxLat = points.first.latitude;
    var minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Widget _buildBottomPanel(
    RideFormState form,
    RouteResult route,
    bool isOffer,
    PublishState publishState,
  ) {
    return Container(
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOffer) _buildDriverInfo(form),
            if (publishState.errorMessage != null) ...[
              Text(
                publishState.errorMessage!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: publishState.isLoading
                    ? null
                    : () => _onConfirm(form, route),
                child: publishState.isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : Text(isOffer ? 'Confirm & Publish' : 'Confirm'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverInfo(RideFormState form) {
    final user = ref.read(authNotifierProvider).user;
    final vehicles = ref.read(myVehiclesProvider).valueOrNull ?? [];
    final vehicle = vehicles.where((v) => v.id == form.vehicleId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primaryLight.withValues(alpha: 0.2),
            child: Text(
              user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'D',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user?.name ?? '', style: AppTypography.labelLarge),
                if (vehicle != null)
                  Text(
                    '${vehicle.model} • ${vehicle.registrationNumber}',
                    style: AppTypography.caption,
                  ),
              ],
            ),
          ),
          Text(
            '₹ ${form.farePerSeat.toStringAsFixed(0)} / seat',
            style: AppTypography.labelLarge.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Future<void> _onConfirm(RideFormState form, RouteResult route) async {
    if (form.mode == RideMode.find) {
      context.push(RouteNames.availableRides);
      return;
    }
    // Offer mode: publish the ride.
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ride = await ref
        .read(publishProvider.notifier)
        .publish(form: form, route: route);
    if (ride != null) {
      ref.read(rideFormProvider.notifier).reset();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Ride published! Passengers can now book seats.'),
          backgroundColor: AppColors.success,
        ),
      );
      router.go(RouteNames.dashboard);
    }
  }
}
