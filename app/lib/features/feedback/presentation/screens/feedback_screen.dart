import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/feedback_provider.dart';

/// Screen for submitting a review after a ride.
class FeedbackScreen extends ConsumerStatefulWidget {
  final String rideId;
  final String bookingId;
  final String revieweeId;
  final String revieweeName;

  const FeedbackScreen({
    super.key,
    required this.rideId,
    required this.bookingId,
    required this.revieweeId,
    required this.revieweeName,
  });

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen>
    with SingleTickerProviderStateMixin {
  int _rating = 0;
  final TextEditingController _commentController = TextEditingController();
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(feedbackNotifierProvider);

    if (formState.isSubmitted) {
      return _buildSuccessScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Rate Your Ride'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.xxl),

            // Avatar + name
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor:
                        AppColors.primaryLight.withValues(alpha: 0.2),
                    child: Text(
                      widget.revieweeName.isNotEmpty
                          ? widget.revieweeName[0].toUpperCase()
                          : 'U',
                      style:
                          AppTypography.h2.copyWith(color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'How was your ride with',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(widget.revieweeName, style: AppTypography.h4),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xxxl),

            // Star rating
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  final starIndex = index + 1;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _rating = starIndex);
                      _animController
                        ..reset()
                        ..forward();
                    },
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      child: ScaleTransition(
                        scale: starIndex == _rating
                            ? _scaleAnim
                            : const AlwaysStoppedAnimation(1.0),
                        child: Icon(
                          starIndex <= _rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 48,
                          color: starIndex <= _rating
                              ? Colors.amber
                              : AppColors.textTertiary,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            if (_rating > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Text(
                  _ratingLabel(_rating),
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xxxl),

            // Comment
            TextField(
              controller: _commentController,
              minLines: 3,
              maxLines: 5,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Add a comment (optional)',
                hintText: 'Tell us about your experience...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),

            if (formState.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 18, color: AppColors.error),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        formState.errorMessage!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xxl),

            // Submit
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _rating > 0 && !formState.isLoading
                    ? _submitFeedback
                    : null,
                child: formState.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit Review'),
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Skip
            Center(
              child: TextButton(
                onPressed: () => context.pop(),
                child: Text(
                  'Skip for now',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    size: 56,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text('Thank You! 🎉', style: AppTypography.h3),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Your review helps build a better\ncarpooling community.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxxl),
                // Stars summary
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    5,
                    (i) => Icon(
                      i < _rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: Colors.amber,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.huge),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => context.pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitFeedback() async {
    await ref.read(feedbackNotifierProvider.notifier).submitFeedback(
          rideId: widget.rideId,
          bookingId: widget.bookingId,
          revieweeId: widget.revieweeId,
          rating: _rating,
          comment: _commentController.text.trim().isEmpty
              ? null
              : _commentController.text.trim(),
        );
  }

  String _ratingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Terrible 😞';
      case 2:
        return 'Poor 😕';
      case 3:
        return 'Okay 🙂';
      case 4:
        return 'Good 😊';
      case 5:
        return 'Excellent! 🤩';
      default:
        return '';
    }
  }
}
