import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      } catch (_) {
        if (mounted) {
          setState(() => _error = 'Search failed. Check your connection.');
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    setState(() => _isResolving = true);
    try {
      final point = await ref
          .read(mapsServiceProvider)
          .getPlaceLocation(suggestion);
      if (mounted) Navigator.pop(context, point);
    } catch (_) {
      if (mounted) {
        setState(() {
          _isResolving = false;
          _error = 'Could not get location details. Try again.';
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
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final s = _suggestions[index];
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
