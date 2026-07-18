import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/feedback_remote_datasource.dart';
import '../../domain/entities/feedback_entity.dart';

// --- DI ---

final feedbackDataSourceProvider = Provider<FeedbackRemoteDataSource>((ref) {
  return FeedbackRemoteDataSource(ref.read(supabaseClientProvider));
});

// --- State ---

class FeedbackFormState {
  final bool isLoading;
  final bool isSubmitted;
  final String? errorMessage;

  const FeedbackFormState({
    this.isLoading = false,
    this.isSubmitted = false,
    this.errorMessage,
  });
}

// --- Notifier ---

class FeedbackNotifier extends StateNotifier<FeedbackFormState> {
  final Ref _ref;

  FeedbackNotifier(this._ref) : super(const FeedbackFormState());

  Future<String?> submitFeedback({
    required String rideId,
    required String bookingId,
    required String revieweeId,
    required int rating,
    String? comment,
  }) async {
    state = const FeedbackFormState(isLoading: true);
    try {
      await _ref.read(feedbackDataSourceProvider).submitFeedback(
            rideId: rideId,
            bookingId: bookingId,
            revieweeId: revieweeId,
            rating: rating,
            comment: comment,
          );
      state = const FeedbackFormState(isSubmitted: true);
      return null;
    } catch (e) {
      final msg = e.toString();
      String error = 'Failed to submit review. Please try again.';
      if (msg.contains('duplicate key') || msg.contains('unique')) {
        error = 'You have already reviewed this ride.';
      } else if (msg.contains('NOT_AUTHORIZED')) {
        error = 'You are not authorized to review this ride.';
      } else if (msg.contains('INVALID_RATING')) {
        error = 'Please select a valid rating (1-5).';
      }
      state = FeedbackFormState(errorMessage: error);
      return error;
    }
  }

  void reset() {
    state = const FeedbackFormState();
  }
}

final feedbackNotifierProvider =
    StateNotifierProvider.autoDispose<FeedbackNotifier, FeedbackFormState>(
        (ref) {
  return FeedbackNotifier(ref);
});

// --- Data providers ---

final userFeedbackProvider =
    FutureProvider.autoDispose.family<List<FeedbackEntity>, String>(
  (ref, userId) {
    return ref.read(feedbackDataSourceProvider).getFeedbackForUser(userId);
  },
);

final userAverageRatingProvider =
    FutureProvider.autoDispose.family<double?, String>(
  (ref, userId) {
    return ref.read(feedbackDataSourceProvider).getAverageRating(userId);
  },
);
