import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/services/maps_service.dart';
import '../../domain/entities/location_point.dart';
import '../providers/ride_provider.dart';

/// A tappable field that opens a place-search bottom sheet.
class LocationInput extends ConsumerWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final LocationPoint? value;
  final ValueChanged<LocationPoint> onSelected;

  const LocationInput({
    super.key,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      onTap: () async {
        final selected = await showModalBottomSheet<LocationPoint>(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => _PlaceSearchSheet(title: label),
        );
        if (selected != null) onSelected(selected);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                value?.address ?? label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: value != null
                    ? AppTypography.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                      )
                    : AppTypography.bodyMedium.copyWith(
                        color: AppColors.textTertiary,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceSearchSheet extends ConsumerStatefulWidget {
  final String title;
  const _PlaceSearchSheet({required this.title});

  @override
  ConsumerState<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends ConsumerState<_PlaceSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = [];
  bool _isLoading = false;
  bool _isResolving = false;
  bool _isLocating = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      if (query.trim().length < 3) {
        setState(() => _suggestions = []);
        return;
      }
      setState(() {
        _isLoading = true;
        _error = null;
      });
      try {
        final results = await ref.read(mapsServiceProvider).autocomplete(query);
        if (mounted) setState(() => _suggestions = results);
      } catch (e) {
        if (mounted) {
          setState(() => _error = _friendlyError(e));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  String _friendlyError(Object e) {
    final msg = e.toString().replaceFirst('Exception: ', '');
    // Keep it under two lines in the UI.
    return msg.length > 220 ? '${msg.substring(0, 220)}…' : msg;
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    setState(() => _isResolving = true);
    try {
      final point = await ref
          .read(mapsServiceProvider)
          .getPlaceLocation(suggestion);
      if (mounted) Navigator.pop(context, point);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isResolving = false;
          _error = _friendlyError(e);
        });
      }
    }
  }

  /// Uses the device GPS to pick the user's current location, then reverse
  /// geocodes it into a readable address (mobile only; web falls back to a
  /// "Current location" label with the coordinates).
  Future<void> _useCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _error = null;
    });
    try {
      // 1. Location services enabled?
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception(
          'Location services are turned off. Enable GPS and try again.',
        );
      }

      // 2. Permission granted?
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission was denied.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permission is permanently denied. Enable it in Settings.',
        );
      }

      // 3. Fetch a fix (with a timeout so the UI can't hang).
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 15));

      // 4. Reverse geocode to a human-readable address (mobile only).
      String address = 'Current location';
      if (!kIsWeb) {
        try {
          final placemarks = await geo.placemarkFromCoordinates(
            position.latitude,
            position.longitude,
          );
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            final parts = <String>[
              if ((p.name ?? '').isNotEmpty && p.name != p.locality) p.name!,
              if ((p.subLocality ?? '').isNotEmpty) p.subLocality!,
              if ((p.locality ?? '').isNotEmpty) p.locality!,
              if ((p.administrativeArea ?? '').isNotEmpty)
                p.administrativeArea!,
            ];
            if (parts.isNotEmpty) address = parts.join(', ');
          }
        } catch (_) {
          // Reverse geocoding failed — keep generic label + coords below.
        }
      }
      if (address == 'Current location') {
        address =
            'Current location '
            '(${position.latitude.toStringAsFixed(4)}, '
            '${position.longitude.toStringAsFixed(4)})';
      }

      if (mounted) {
        Navigator.pop(
          context,
          LocationPoint(
            address: address,
            lat: position.latitude,
            lng: position.longitude,
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _error = 'Could not get a GPS fix in time. Try again outdoors.';
          _isLocating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(e);
          _isLocating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.md),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: AppTypography.h4),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    onChanged: _onQueryChanged,
                    decoration: InputDecoration(
                      hintText: 'Search for a place...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _isLoading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                ),
                child: Text(
                  _error!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
            if (_isResolving)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: CircularProgressIndicator(),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _suggestions.length + 1,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return ListTile(
                        leading: _isLocating
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.my_location_rounded,
                                color: AppColors.primary,
                              ),
                        title: Text(
                          'Use my current location',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          _isLocating
                              ? 'Fetching GPS…'
                              : 'Pick the spot you\'re standing at',
                          style: AppTypography.bodySmall,
                        ),
                        onTap: _isLocating ? null : _useCurrentLocation,
                      );
                    }
                    final s = _suggestions[index - 1];
                    return ListTile(
                      leading: const Icon(
                        Icons.location_on_outlined,
                        color: AppColors.textTertiary,
                      ),
                      title: Text(
                        s.primaryText,
                        style: AppTypography.bodyMedium,
                      ),
                      subtitle: s.secondaryText.isNotEmpty
                          ? Text(
                              s.secondaryText,
                              style: AppTypography.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      onTap: () => _selectSuggestion(s),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
