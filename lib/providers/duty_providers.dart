import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/remote/supabase_duty_repository.dart';
import '../models/planning.dart';
import '../repositories/duty_repository.dart';
import '../services/duty_service.dart';
import 'auth_providers.dart';

final dutyRepositoryProvider = Provider<DutyRepository>(
  (ref) => SupabaseDutyRepository(Supabase.instance.client),
);
// L'identità nella chiave separa la cache Riverpod tra account.
final dutiesProvider = FutureProvider.autoDispose.family<List<Duty>, String>((
  ref,
  userId,
) async {
  await ref.watch(currentProfileProvider(userId).future);
  return ref.watch(dutyRepositoryProvider).list();
});
final dutyServiceProvider = FutureProvider.autoDispose
    .family<DutyService, String>(
      (ref, userId) async => DutyService(
        ref.watch(dutyRepositoryProvider),
        await ref.watch(currentProfileProvider(userId).future),
      ),
    );
