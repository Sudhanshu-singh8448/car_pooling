import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/maps_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/ride_remote_datasource.dart';
import '../../data/repositories/ride_repository.dart';
import '../../domain/entities/booking_entity.dart';
import '../../domain/entities/location_point.dart';
import '../../domain/entities/ride_entity.dart';
import '../../domain/entities/ride_match.dart';

// --- DI providers ---

final mapsServiceProvider = Provider<MapsService>((ref) => MapsService());

final rideRemoteDataSourceProvider = Provider<RideRemoteDataSource>((ref) {
  return RideRemoteDataSource(ref.read(supabaseClientProvider));
});

final rideRepositoryProvider = Provider<RideRepository>((ref) {
  return RideRepository(ref.read(rideRemoteDataSourceProvider));
});

// --- Ride form state (shared by Find & Offer tabs) ---

enum RideMode { find, offer }

class RideFormState {
  final RideMode mode;
  final LocationPoint? pickup;
  final LocationPoint? destination;
  final DateTime departureTime;
  final int seats;
  final double farePerSeat;
  final bool isRecurring;
  final Set<String> recurringDays;
  final String? vehicleId;

  RideFormState({
    this.mode = RideMode.find,
    this.pickup,
    this.destination,
    DateTime? departureTime,
    this.seats = 1,
    this.farePerSeat = 0,
    this.isRecurring = false,
    this.recurringDays = const {},
    this.vehicleId,
  }) : departureTime =
           departureTime ?? DateTime.now().add(const Duration(hours: 1));

  bool get isValid => pickup != null && destination != null;

  RideFormState copyWith({
    RideMode? mode,
    LocationPoint? pickup,
    LocationPoint? destination,
    DateTime? departureTime,
    int? seats,
    double? farePerSeat,
    bool? isRecurring,
    Set<String>? recurringDays,
    String? vehicleId,
  }) {
    return RideFormState(
      mode: mode ?? this.mode,
      pickup: pickup ?? this.pickup,
      destination: destination ?? this.destination,
      departureTime: departureTime ?? this.departureTime,
      seats: seats ?? this.seats,
      farePerSeat: farePerSeat ?? this.farePerSeat,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringDays: recurringDays ?? this.recurringDays,
      vehicleId: vehicleId ?? this.vehicleId,
    );
  }
}

class RideFormNotifier extends StateNotifier<RideFormState> {
  RideFormNotifier() : super(RideFormState());

  void setMode(RideMode mode) => state = state.copyWith(mode: mode);
  void setPickup(LocationPoint point) => state = state.copyWith(pickup: point);
  void setDestination(LocationPoint point) =>
      state = state.copyWith(destination: point);
  void setDepartureTime(DateTime time) =>
      state = state.copyWith(departureTime: time);
  void setSeats(int seats) => state = state.copyWith(seats: seats);
  void setFare(double fare) => state = state.copyWith(farePerSeat: fare);
  void setVehicle(String vehicleId) =>
      state = state.copyWith(vehicleId: vehicleId);
  void toggleRecurring() =>
      state = state.copyWith(isRecurring: !state.isRecurring);

  void toggleRecurringDay(String day) {
    final days = Set<String>.from(state.recurringDays);
    days.contains(day) ? days.remove(day) : days.add(day);
    state = state.copyWith(recurringDays: days);
  }

  void swapLocations() {
    final pickup = state.pickup;
    final destination = state.destination;
    if (pickup == null || destination == null) return;
    state = state.copyWith(pickup: destination, destination: pickup);
  }

  void reset() => state = RideFormState(mode: state.mode);
}

final rideFormProvider = StateNotifierProvider<RideFormNotifier, RideFormState>(
  (ref) {
    return RideFormNotifier();
  },
);

// --- Route computation (Route Confirmation screen) ---

final routeProvider = FutureProvider.autoDispose
    .family<RouteResult, ({LocationPoint origin, LocationPoint destination})>((
      ref,
      args,
    ) async {
      return ref
          .read(mapsServiceProvider)
          .computeRoute(args.origin, args.destination);
    });

// --- Ride search (Available Rides screen) ---

final availableRidesProvider = FutureProvider.autoDispose<List<RideMatch>>((
  ref,
) async {
  final form = ref.read(rideFormProvider);
  if (!form.isValid) return [];
  return ref
      .read(rideRepositoryProvider)
      .searchRides(
        pickup: form.pickup!,
        destination: form.destination!,
        date: form.departureTime,
        seats: form.seats,
      );
});

// --- Recurring ride suggestions ---
// Returns rides that repeat on the passenger's selected weekdays. Each
// map has an `is_exact_match` bool + `match_count` int so the UI can
// group results into "Exact Matches" and "Other Suggested Matches".
final recurringRidesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final form = ref.read(rideFormProvider);
  if (!form.isValid || form.recurringDays.isEmpty) return const [];
  return ref.read(rideRemoteDataSourceProvider).searchRecurringRides(
        pickup: form.pickup!,
        destination: form.destination!,
        days: form.recurringDays.toList(),
        seats: form.seats,
      );
});

// --- Booking action ---

class BookingActionState {
  final bool isLoading;
  final String? bookingRideId;
  final BookingEntity? booking;
  final String? errorMessage;

  const BookingActionState({
    this.isLoading = false,
    this.bookingRideId,
    this.booking,
    this.errorMessage,
  });
}

class BookingActionNotifier extends StateNotifier<BookingActionState> {
  final RideRepository _repository;

  BookingActionNotifier(this._repository) : super(const BookingActionState());

  Future<BookingEntity?> book(String rideId, int seats) async {
    state = BookingActionState(isLoading: true, bookingRideId: rideId);
    try {
      final booking = await _repository.bookRide(rideId: rideId, seats: seats);
      state = BookingActionState(booking: booking);
      return booking;
    } catch (e) {
      state = BookingActionState(errorMessage: _friendlyBookingError(e));
      return null;
    }
  }

  static String _friendlyBookingError(Object e) {
    final msg = e.toString();
    if (msg.contains('INSUFFICIENT_SEATS')) {
      return 'Not enough seats left on this ride.';
    }
    if (msg.contains('ALREADY_BOOKED')) {
      return 'You have already booked this ride.';
    }
    if (msg.contains('CANNOT_BOOK_OWN_RIDE')) {
      return 'You cannot book your own ride.';
    }
    if (msg.contains('RIDE_NOT_AVAILABLE')) {
      return 'This ride is no longer available.';
    }
    return 'Booking failed. Please try again.';
  }
}

final bookingActionProvider =
    StateNotifierProvider<BookingActionNotifier, BookingActionState>((ref) {
      return BookingActionNotifier(ref.read(rideRepositoryProvider));
    });

// --- Publish action ---

class PublishState {
  final bool isLoading;
  final RideEntity? publishedRide;
  final String? errorMessage;

  const PublishState({
    this.isLoading = false,
    this.publishedRide,
    this.errorMessage,
  });
}

class PublishNotifier extends StateNotifier<PublishState> {
  final RideRepository _repository;

  PublishNotifier(this._repository) : super(const PublishState());

  Future<RideEntity?> publish({
    required RideFormState form,
    required RouteResult route,
  }) async {
    state = const PublishState(isLoading: true);
    try {
      final ride = await _repository.publishRide(
        vehicleId: form.vehicleId!,
        pickup: form.pickup!,
        destination: form.destination!,
        departureTime: form.departureTime,
        totalSeats: form.seats,
        farePerSeat: form.farePerSeat,
        routePolyline: route.encodedPolyline,
        distanceKm: route.distanceKm,
        durationMinutes: route.durationMinutes,
        isRecurring: form.isRecurring,
        recurringDays: form.recurringDays.isEmpty
            ? null
            : form.recurringDays.join(','),
      );
      state = PublishState(publishedRide: ride);
      return ride;
    } catch (e) {
      state = const PublishState(
        errorMessage: 'Failed to publish ride. Please try again.',
      );
      return null;
    }
  }
}

final publishProvider = StateNotifierProvider<PublishNotifier, PublishState>((
  ref,
) {
  return PublishNotifier(ref.read(rideRepositoryProvider));
});
