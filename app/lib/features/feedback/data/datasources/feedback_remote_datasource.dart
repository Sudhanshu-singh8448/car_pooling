import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/feedback_entity.dart';

class FeedbackRemoteDataSource {
  final SupabaseClient _client;

  FeedbackRemoteDataSource(this._client);

  String get _userId => _client.auth.currentUser!.id;

  /// Submit feedback for a ride via the atomic RPC.
  Future<FeedbackEntity> submitFeedback({
    required String rideId,
    required String bookingId,
    required String revieweeId,
    required int rating,
    String? comment,
  }) async {
    final data = await _client.rpc(
      'submit_feedback',
      params: {
        'p_ride_id': rideId,
        'p_booking_id': bookingId,
        'p_reviewee_id': revieweeId,
        'p_rating': rating,
        'p_comment': comment,
      },
    );
    return FeedbackEntity.fromMap(Map<String, dynamic>.from(data as Map));
  }

  /// Fetch all reviews about a user (as the reviewee).
  Future<List<FeedbackEntity>> getFeedbackForUser(String userId) async {
    final data = await _client
        .from('feedback')
        .select()
        .eq('reviewee_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    return (data as List)
        .map(
          (f) => FeedbackEntity.fromMap(Map<String, dynamic>.from(f as Map)),
        )
        .toList();
  }

  /// Get all feedback for a specific ride.
  Future<List<FeedbackEntity>> getFeedbackForRide(String rideId) async {
    final data = await _client
        .from('feedback')
        .select()
        .eq('ride_id', rideId)
        .order('created_at', ascending: false);
    return (data as List)
        .map(
          (f) => FeedbackEntity.fromMap(Map<String, dynamic>.from(f as Map)),
        )
        .toList();
  }

  /// Check if the current user has already submitted feedback for this booking.
  Future<bool> hasSubmittedFeedback(String bookingId) async {
    final data = await _client
        .from('feedback')
        .select('id')
        .eq('booking_id', bookingId)
        .eq('reviewer_id', _userId)
        .maybeSingle();
    return data != null;
  }

  /// Get the average rating for a user.
  Future<double?> getAverageRating(String userId) async {
    final data = await _client
        .from('feedback')
        .select('rating')
        .eq('reviewee_id', userId);
    final ratings = (data as List).map((r) => (r as Map)['rating'] as int);
    if (ratings.isEmpty) return null;
    return ratings.reduce((a, b) => a + b) / ratings.length;
  }
}
