import 'package:equatable/equatable.dart';

import 'ride_entity.dart';

const recurringWeekdays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

class RecurringRideEntity extends Equatable {
  final RideEntity ride;
  final List<String> recurrenceDays;
  final int tripsPerWeek;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isActive;

  const RecurringRideEntity({
    required this.ride,
    required this.recurrenceDays,
    required this.tripsPerWeek,
    required this.startDate,
    this.endDate,
    this.isActive = true,
  });

  factory RecurringRideEntity.fromMap(Map<String, dynamic> map) {
    final days = _stringList(map['recurrence_days'] ?? map['recurring_days']);
    final rideMap = Map<String, dynamic>.from(map);
    if (map['ride_id'] != null) {
      rideMap['id'] = map['ride_id'];
    }
    rideMap['is_recurring'] = true;
    rideMap['recurring_days'] = days.join(',');

    return RecurringRideEntity(
      ride: RideEntity.fromMap(rideMap),
      recurrenceDays: days,
      tripsPerWeek: (map['trips_per_week'] as num?)?.toInt() ?? days.length,
      startDate: _dateOrDefault(map['start_date']),
      endDate: _dateOrNull(map['end_date']),
      isActive: map['is_active'] as bool? ?? true,
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    if (value is String) {
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static DateTime _dateOrDefault(Object? value) {
    final parsed = _dateOrNull(value);
    return parsed ?? DateTime.now();
  }

  static DateTime? _dateOrNull(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  int get matchingDayCount => recurrenceDays.length;

  @override
  List<Object?> get props => [
    ride.id,
    recurrenceDays,
    tripsPerWeek,
    startDate,
    endDate,
    isActive,
  ];
}

class RecurringRideMatch extends RecurringRideEntity {
  final List<String> matchingDays;
  final List<String> requestedDays;
  final int matchCount;
  final int totalRequested;
  final double matchPercentage;
  final bool isExactMatch;

  const RecurringRideMatch({
    required super.ride,
    required super.recurrenceDays,
    required super.tripsPerWeek,
    required super.startDate,
    super.endDate,
    super.isActive,
    required this.matchingDays,
    required this.requestedDays,
    required this.matchCount,
    required this.totalRequested,
    required this.matchPercentage,
    required this.isExactMatch,
  });

  factory RecurringRideMatch.fromMap(Map<String, dynamic> map) {
    final base = RecurringRideEntity.fromMap(map);
    final matchingDays = _days(map['matching_days']);
    final requestedDays = _days(map['requested_days']);
    final matchCount =
        (map['match_count'] as num?)?.toInt() ?? matchingDays.length;
    final totalRequested =
        (map['total_requested'] as num?)?.toInt() ?? requestedDays.length;
    final percentage =
        (map['match_percentage'] as num?)?.toDouble() ??
        (totalRequested == 0 ? 0 : matchCount / totalRequested * 100);

    return RecurringRideMatch(
      ride: base.ride,
      recurrenceDays: base.recurrenceDays,
      tripsPerWeek: base.tripsPerWeek,
      startDate: base.startDate,
      endDate: base.endDate,
      isActive: base.isActive,
      matchingDays: matchingDays,
      requestedDays: requestedDays,
      matchCount: matchCount,
      totalRequested: totalRequested,
      matchPercentage: percentage,
      isExactMatch: map['is_exact_match'] as bool? ?? false,
    );
  }

  static List<String> _days(Object? value) {
    if (value is List) return value.map((item) => item.toString()).toList();
    if (value is String) {
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }
}
