import 'package:flutter_test/flutter_test.dart';

import 'package:car_pooling/features/ride/domain/entities/recurring_ride_entity.dart';

Map<String, dynamic> _matchMap({
  required bool exact,
  required List<String> matchingDays,
  required int matchCount,
}) {
  return {
    'id': 'ride-1',
    'ride_id': 'ride-1',
    'driver_id': 'driver-1',
    'driver_name': 'Driver',
    'vehicle_id': 'vehicle-1',
    'vehicle_model': 'Car',
    'vehicle_registration': 'GJ01AA0001',
    'pickup_address': 'Pickup',
    'pickup_lat': 23.0,
    'pickup_lng': 72.0,
    'destination_address': 'Destination',
    'destination_lat': 23.1,
    'destination_lng': 72.1,
    'departure_time': '2026-07-20T08:00:00.000Z',
    'total_seats': 4,
    'available_seats': 3,
    'fare_per_seat': 100,
    'status': 'published',
    'recurring_days': ['Monday', 'Wednesday', 'Friday'],
    'trips_per_week': 3,
    'start_date': '2026-07-20',
    'matching_days': matchingDays,
    'requested_days': ['Monday', 'Wednesday', 'Friday'],
    'match_count': matchCount,
    'total_requested': 3,
    'match_percentage': matchCount / 3 * 100,
    'is_exact_match': exact,
  };
}

void main() {
  test('parses an exact recurring match and its weekday arrays', () {
    final match = RecurringRideMatch.fromMap(
      _matchMap(
        exact: true,
        matchingDays: ['Monday', 'Wednesday', 'Friday'],
        matchCount: 3,
      ),
    );

    expect(match.isExactMatch, isTrue);
    expect(match.matchCount, 3);
    expect(match.matchPercentage, 100);
    expect(match.ride.isRecurring, isTrue);
    expect(
      match.recurrenceDays,
      recurringWeekdays
          .where((day) => ['Monday', 'Wednesday', 'Friday'].contains(day))
          .toList(),
    );
  });

  test('parses a partial match score for suggested results', () {
    final match = RecurringRideMatch.fromMap(
      _matchMap(
        exact: false,
        matchingDays: ['Monday', 'Wednesday'],
        matchCount: 2,
      ),
    );

    expect(match.isExactMatch, isFalse);
    expect(match.matchCount, 2);
    expect(match.matchPercentage, closeTo(66.67, 0.01));
    expect(match.matchingDays, ['Monday', 'Wednesday']);
  });
}
