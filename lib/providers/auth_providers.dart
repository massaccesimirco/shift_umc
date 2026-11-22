import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/remote/supabase_auth_repository.dart';
import '../models/planning.dart';
import '../repositories/auth_repository.dart';
import '../services/auth_service.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(Supabase.instance.client),
);
final authServiceProvider = Provider(
  (ref) => AuthService(ref.watch(authRepositoryProvider)),
);
final sessionUserProvider = StreamProvider<String?>(
  (ref) => ref.watch(authRepositoryProvider).userIds,
);
final currentProfileProvider = FutureProvider.autoDispose
    .family<UserProfile, String>(
      (ref, userId) => ref.watch(authServiceProvider).requireProfile(userId),
      // Lascio il nuovo tentativo alla schermata, anche quando il profilo non è accessibile.
      retry: (retryCount, error) => null,
    );
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
    state = await AsyncValue.guard(
      () => ref.read(authServiceProvider).signOut(),
    );
  }
}
