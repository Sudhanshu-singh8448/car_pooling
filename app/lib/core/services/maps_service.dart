import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';
import '../../features/ride/domain/entities/location_point.dart';

/// A place suggestion returned by autocomplete.
class PlaceSuggestion {
  final String placeId;
  final String primaryText;
  final String secondaryText;

  const PlaceSuggestion({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
  });
}

/// A computed route between two points.
class RouteResult {
  final String encodedPolyline;
  final double distanceKm;
  final int durationMinutes;
  final List<LatLng> points;

  const RouteResult({
    required this.encodedPolyline,
    required this.distanceKm,
    required this.durationMinutes,
    required this.points,
  });
}

/// Wrapper around Google Places API (New) and Routes API v2.
/// Both support CORS, so they work on Flutter web as well as mobile.
class MapsService {
  final http.Client _client;

  MapsService({http.Client? client}) : _client = client ?? http.Client();

  static const _apiKey = AppConstants.googleMapsApiKey;

  /// Autocomplete place search (Places API New).
  Future<List<PlaceSuggestion>> autocomplete(String input) async {
    if (input.trim().length < 3) return [];
    final response = await _client.post(
      Uri.parse('https://places.googleapis.com/v1/places:autocomplete'),
      headers: {'Content-Type': 'application/json', 'X-Goog-Api-Key': _apiKey},
      body: jsonEncode({
        'input': input,
        // Bias towards India (app demo region); adjust as needed.
        'locationBias': {
          'rectangle': {
            'low': {'latitude': 6.5, 'longitude': 68.0},
            'high': {'latitude': 35.7, 'longitude': 97.5},
          },
        },
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Autocomplete failed (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final suggestions = data['suggestions'] as List? ?? [];
    return suggestions
        .map((s) {
          final p = s['placePrediction'] as Map<String, dynamic>?;
          if (p == null) return null;
          final structured = p['structuredFormat'] as Map<String, dynamic>?;
          return PlaceSuggestion(
            placeId: p['placeId'] as String,
            primaryText:
                structured?['mainText']?['text'] as String? ??
                p['text']?['text'] as String? ??
                '',
            secondaryText:
                structured?['secondaryText']?['text'] as String? ?? '',
          );
        })
        .whereType<PlaceSuggestion>()
        .toList();
  }

  /// Resolve a place ID to coordinates + formatted address.
  Future<LocationPoint> getPlaceLocation(PlaceSuggestion suggestion) async {
    final response = await _client.get(
      Uri.parse(
        'https://places.googleapis.com/v1/places/${suggestion.placeId}',
      ),
      headers: {
        'X-Goog-Api-Key': _apiKey,
        'X-Goog-FieldMask': 'location,formattedAddress,displayName',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Place details failed (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final location = data['location'] as Map<String, dynamic>;
    return LocationPoint(
      address: suggestion.secondaryText.isNotEmpty
          ? '${suggestion.primaryText}, ${suggestion.secondaryText}'
          : data['formattedAddress'] as String? ?? suggestion.primaryText,
      lat: (location['latitude'] as num).toDouble(),
      lng: (location['longitude'] as num).toDouble(),
    );
  }

  /// Compute driving route (Routes API v2). Falls back to a straight-line
  /// estimate if the API is unavailable so the app remains demoable.
  Future<RouteResult> computeRoute(
    LocationPoint origin,
    LocationPoint destination,
  ) async {
    try {
      final response = await _client.post(
        Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes'),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask':
              'routes.polyline.encodedPolyline,routes.distanceMeters,routes.duration',
        },
        body: jsonEncode({
          'origin': {
            'location': {
              'latLng': {'latitude': origin.lat, 'longitude': origin.lng},
            },
          },
          'destination': {
            'location': {
              'latLng': {
                'latitude': destination.lat,
                'longitude': destination.lng,
              },
            },
          },
          'travelMode': 'DRIVE',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List? ?? [];
        if (routes.isNotEmpty) {
          final route = routes.first as Map<String, dynamic>;
          final encoded =
              route['polyline']?['encodedPolyline'] as String? ?? '';
          final distanceMeters = (route['distanceMeters'] as num?) ?? 0;
          final durationStr = route['duration'] as String? ?? '0s';
          final durationSeconds =
              int.tryParse(durationStr.replaceAll('s', '')) ?? 0;
          return RouteResult(
            encodedPolyline: encoded,
            distanceKm: distanceMeters / 1000,
            durationMinutes: (durationSeconds / 60).ceil(),
            points: decodePolyline(encoded),
          );
        }
      }
    } catch (_) {
      // Fall through to the straight-line estimate below.
    }
    return _straightLineFallback(origin, destination);
  }

  /// Decode an encoded polyline string into map coordinates.
  static List<LatLng> decodePolyline(String encoded) {
    if (encoded.isEmpty) return [];
    return PolylinePoints()
        .decodePolyline(encoded)
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
  }

  RouteResult _straightLineFallback(
    LocationPoint origin,
    LocationPoint destination,
  ) {
    final km = haversineKm(
      origin.lat,
      origin.lng,
      destination.lat,
      destination.lng,
    );
    // Road distance ≈ 1.3x straight line; avg city speed ≈ 35 km/h.
    final roadKm = km * 1.3;
    return RouteResult(
      encodedPolyline: '',
      distanceKm: double.parse(roadKm.toStringAsFixed(1)),
      durationMinutes: math.max(1, (roadKm / 35 * 60).round()),
      points: [
        LatLng(origin.lat, origin.lng),
        LatLng(destination.lat, destination.lng),
      ],
    );
  }

  /// Haversine distance in kilometers.
  static double haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
