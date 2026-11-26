import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/remote/supabase_employee_planning_repository.dart';
import '../models/access_failure.dart';
import '../models/planning.dart';
import '../models/local_planning.dart';
import '../models/network_failure.dart';
import '../repositories/employee_planning_repository.dart';
import 'auth_providers.dart';
import 'local_planning_providers.dart';

final employeePlanningRepositoryProvider = Provider<EmployeePlanningRepository>(
  (ref) => SupabaseEmployeePlanningRepository(Supabase.instance.client),
);
final remoteTodayProvider = Provider.autoDispose<DateTime>((ref) {
  final now = DateTime.now();
  // Ricalcolo il giorno alla mezzanotte locale e libero il timer quando esco dalla vista.
  final midnight = DateTime(now.year, now.month, now.day + 1);
  final timer = Timer(midnight.difference(now), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return dateOnly(now);
});
final employeePlanningProvider = FutureProvider.autoDispose
    .family<PlanningView, ({String userId, DateTime monday})>((
      ref,
      selection,
    ) async {
      final repository = ref.watch(employeePlanningRepositoryProvider);
      final store = ref.watch(localPlanningStoreProvider);
      final profileFuture = ref.watch(
        currentProfileProvider(selection.userId).future,
      );
      final generation = store.generation(selection.userId);
      var disposed = false;
      ref.onDispose(() => disposed = true);
      final monday = mondayOf(selection.monday);
      try {
        final profile = await profileFuture;
        if (!profile.active ||
            profile.role != UserRole.employee ||
            profile.id != selection.userId) {
          throw const AccessFailure(
            'La pianificazione personale è riservata ai dipendenti attivi.',
          );
        }
        final result = await repository
            .load(monday, profile.id)
            .timeout(const Duration(seconds: 15));
        if (result != null &&
            (result.week.status != WeekStatus.published ||
                !sameDate(result.week.startDate, monday) ||
                result.assignments.any(
                  (a) =>
                      a.employeeId != profile.id ||
                      a.weekPlanId != result.week.id,
                ))) {
          throw const AccessFailure(
            'Pianificazione non disponibile. Aggiorna e riprova.',
          );
        }
        if (disposed) return PlanningView(planning: result);
        try {
          if (result == null) {
            // Rimuovo la copia di una settimana che il server non restituisce più.
            await store.removeWeek(selection.userId, monday, generation);
            return const PlanningView(planning: null);
          }
          final savedAt = await store.save(
            selection.userId,
            result,
            generation,
          );
          return PlanningView(planning: result, savedAt: savedAt);
        } catch (_) {
          // Non nascondo i dati online se il dispositivo non riesce a conservarli.
          return PlanningView(planning: result, cacheWriteFailed: true);
        }
      } catch (error) {
        if (disposed) rethrow;
        if (!isNetworkFailure(error)) {
          if (error is AccessFailure ||
              (error is PostgrestException && error.code == '42501')) {
            try {
              await store.clearUser(selection.userId);
            } catch (_) {}
          }
          rethrow;
        }
        final cached = await store.read(selection.userId, monday);
        if (cached == null) {
          throw const AccessFailure(
            'Connessione non disponibile e nessuna copia locale salvata per questa settimana.',
          );
        }
        return PlanningView(
          planning: cached.planning,
          savedAt: cached.savedAt,
          fromCache: true,
        );
      }
    }, retry: (count, error) => null);
