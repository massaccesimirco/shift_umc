import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/remote/supabase_auth_repository.dart';
import '../models/planning.dart';
import '../models/access_failure.dart';
import 'local_planning_providers.dart';
import '../repositories/auth_repository.dart';
import '../services/auth_service.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(Supabase.instance.client),
);
final authServiceProvider = Provider(
  (ref) => AuthService(ref.watch(authRepositoryProvider)),
);
final sessionUserProvider = StreamProvider<String?>((ref) async* {
  final repository = ref.watch(authRepositoryProvider);
  final store = ref.watch(localPlanningStoreProvider);
  String? previous;
  await for (final id in repository.userIds) {
    if (previous != null && previous != id) {
      try {
        await store.clearUser(previous);
      } catch (_) {
        // Non trattengo una sessione terminata se lo storage locale è indisponibile.
      }
    }
    previous = id;
    yield id;
  }
});
final currentProfileProvider = FutureProvider.autoDispose
    .family<UserProfile, String>((ref, userId) async {
      final service = ref.watch(authServiceProvider);
      final store = ref.watch(localPlanningStoreProvider);
      try {
        final profile = await service
            .requireProfile(userId)
            .timeout(const Duration(seconds: 15));
        if (profile.role != UserRole.employee) {
          try {
            await store.clearUser(userId);
          } catch (_) {}
        }
        return profile;
      } on AccessFailure {
        // Cancello la copia dopo un rifiuto esplicito; un errore di rete resta distinguibile.
        try {
          await store.clearUser(userId);
        } catch (_) {}
        rethrow;
      }
    }, retry: (retryCount, error) => null);
final authActionProvider = AsyncNotifierProvider<AuthActions, void>(
  AuthActions.new,
);

class AuthActions extends AsyncNotifier<void> {
  @override
  void build() {}
  Future<void> signIn(String email, String password) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authServiceProvider).signIn(email, password),
    );
  }

  Future<void> signOut() async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final id = ref.read(sessionUserProvider).asData?.value;
      if (id != null) {
        try {
          await ref.read(localPlanningStoreProvider).clearUser(id);
        } catch (_) {
          throw const AccessFailure(
            'Non riesco a cancellare la copia locale. Riprova prima di uscire.',
          );
        }
      }
      await ref.read(authServiceProvider).signOut();
    });
  }
}
