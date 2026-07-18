import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/presentation/providers/auth_provider.dart';

class AdminEmployee {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? department;
  final String role;
  final String platformAccess;

  const AdminEmployee({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.department,
    required this.role,
    required this.platformAccess,
  });

  factory AdminEmployee.fromMap(Map<String, dynamic> map) => AdminEmployee(
    id: map['id'] as String,
    name: map['name'] as String? ?? '—',
    email: map['email'] as String? ?? '—',
    phone: map['phone'] as String?,
    department: map['department'] as String?,
    role: map['role'] as String? ?? 'employee',
    platformAccess: map['platform_access'] as String? ?? 'granted',
  );
}

class AdminVehicle {
  final String id;
  final String model;
  final String registrationNumber;
  final int seatingCapacity;
  final String status;
  final String ownerName;

  const AdminVehicle({
    required this.id,
    required this.model,
    required this.registrationNumber,
    required this.seatingCapacity,
    required this.status,
    required this.ownerName,
  });

  factory AdminVehicle.fromMap(Map<String, dynamic> map) => AdminVehicle(
    id: map['id'] as String,
    model: map['model'] as String,
    registrationNumber: map['registration_number'] as String,
    seatingCapacity: (map['seating_capacity'] as num).toInt(),
    status: map['status'] as String,
    ownerName: (map['profiles'] as Map?)?['name'] as String? ?? '—',
  );
}

class OrgSettings {
  final String? id;
  final String name;
  final String? industry;
  final String? address;
  final double fuelCostPerLiter;
  final double costPerKm;
  final double travelCostPerKm;

  const OrgSettings({
    this.id,
    required this.name,
    this.industry,
    this.address,
    required this.fuelCostPerLiter,
    required this.costPerKm,
    required this.travelCostPerKm,
  });

  factory OrgSettings.fromMap(Map<String, dynamic> map) => OrgSettings(
    id: map['id'] as String,
    name: map['name'] as String,
    industry: map['industry'] as String?,
    address: map['address'] as String?,
    fuelCostPerLiter: ((map['fuel_cost_per_liter'] as num?) ?? 100).toDouble(),
    costPerKm: ((map['cost_per_km'] as num?) ?? 12).toDouble(),
    travelCostPerKm: ((map['travel_cost_per_km'] as num?) ?? 15).toDouble(),
  );
}

class AdminStats {
  final int totalEmployees;
  final int totalVehicles;
  final int ridesThisMonth;

  const AdminStats({
    required this.totalEmployees,
    required this.totalVehicles,
    required this.ridesThisMonth,
  });
}

final adminEmployeesProvider = FutureProvider.autoDispose<List<AdminEmployee>>((
  ref,
) async {
  final client = ref.read(supabaseClientProvider);
  final data = await client.from('profiles').select().order('name');
  return (data as List)
      .map((m) => AdminEmployee.fromMap(Map<String, dynamic>.from(m as Map)))
      .toList();
});

final adminVehiclesProvider = FutureProvider.autoDispose<List<AdminVehicle>>((
  ref,
) async {
  final client = ref.read(supabaseClientProvider);
  final data = await client
      .from('vehicles')
      .select('*, profiles!vehicles_owner_id_fkey(name)')
      .eq('is_deleted', false)
      .order('created_at');
  return (data as List)
      .map((m) => AdminVehicle.fromMap(Map<String, dynamic>.from(m as Map)))
      .toList();
});

final adminStatsProvider = FutureProvider.autoDispose<AdminStats>((ref) async {
  final client = ref.read(supabaseClientProvider);
  final monthStart = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  ).toUtc().toIso8601String();
  final employees = await client.from('profiles').count();
  final vehicles = await client
      .from('vehicles')
      .count()
      .eq('is_deleted', false);
  final rides = await client
      .from('rides')
      .count()
      .gte('created_at', monthStart);
  return AdminStats(
    totalEmployees: employees,
    totalVehicles: vehicles,
    ridesThisMonth: rides,
  );
});

final orgSettingsProvider = FutureProvider.autoDispose<OrgSettings?>((
  ref,
) async {
  final client = ref.read(supabaseClientProvider);
  final data = await client
      .from('organizations')
      .select()
      .eq('is_deleted', false)
      .limit(1)
      .maybeSingle();
  if (data == null) return null;
  return OrgSettings.fromMap(data);
});

/// Admin mutations.
class AdminActionNotifier extends StateNotifier<bool> {
  final Ref _ref;

  AdminActionNotifier(this._ref) : super(false);

  SupabaseClient get _client => _ref.read(supabaseClientProvider);

  Future<String?> toggleEmployeeAccess(
    String profileId,
    String currentAccess,
  ) async {
    state = true;
    try {
      final next = currentAccess == 'granted' ? 'revoked' : 'granted';
      await _client
          .from('profiles')
          .update({'platform_access': next})
          .eq('id', profileId);
      _ref.invalidate(adminEmployeesProvider);
      return null;
    } catch (_) {
      return 'Failed to update access.';
    } finally {
      state = false;
    }
  }

  Future<String?> toggleVehicleStatus(
    String vehicleId,
    String currentStatus,
  ) async {
    state = true;
    try {
      final next = currentStatus == 'active' ? 'inactive' : 'active';
      await _client
          .from('vehicles')
          .update({'status': next})
          .eq('id', vehicleId);
      _ref.invalidate(adminVehiclesProvider);
      return null;
    } catch (_) {
      return 'Failed to update vehicle status.';
    } finally {
      state = false;
    }
  }

  Future<String?> saveOrgSettings(OrgSettings settings) async {
    state = true;
    try {
      final payload = {
        'name': settings.name,
        'industry': settings.industry,
        'address': settings.address,
        'fuel_cost_per_liter': settings.fuelCostPerLiter,
        'cost_per_km': settings.costPerKm,
        'travel_cost_per_km': settings.travelCostPerKm,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (settings.id == null) {
        await _client.from('organizations').insert(payload);
      } else {
        await _client
            .from('organizations')
            .update(payload)
            .eq('id', settings.id!);
      }
      _ref.invalidate(orgSettingsProvider);
      return null;
    } catch (_) {
      return 'Failed to save organization settings.';
    } finally {
      state = false;
    }
  }
}

final adminActionProvider = StateNotifierProvider<AdminActionNotifier, bool>((
  ref,
) {
  return AdminActionNotifier(ref);
});
