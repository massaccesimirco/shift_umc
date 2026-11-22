import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/remote/supabase_employee_repository.dart';
import '../models/planning.dart';
import '../repositories/employee_repository.dart';
import '../services/employee_service.dart';
import 'auth_providers.dart';

final employeeRepositoryProvider = Provider<EmployeeRepository>(
  (ref) => SupabaseEmployeeRepository(Supabase.instance.client),
);
final employeeServiceProvider = FutureProvider.autoDispose
    .family<EmployeeService, String>(
      (ref, userId) async => EmployeeService(
        ref.watch(employeeRepositoryProvider),
        await ref.watch(currentProfileProvider(userId).future),
      ),
    );
final employeesProvider = FutureProvider.autoDispose
    .family<List<UserProfile>, String>(
      (ref, userId) async =>
          (await ref.watch(employeeServiceProvider(userId).future)).list(),
    );
