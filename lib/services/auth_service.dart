import '../models/access_failure.dart';
import '../models/planning.dart';
import '../repositories/auth_repository.dart';

class AuthService {
  const AuthService(this.repository);
  final AuthRepository repository;
  Future<void> signIn(String email, String password) =>
      repository.signIn(email.trim(), password);
  Future<void> signOut() => repository.signOut();
  Future<UserProfile> requireProfile(String userId) async {
    final profile = await repository.profileFor(userId);
    // Le RLS nascondono un profilo disattivato: può arrivare null anche in quel caso.
    if (profile == null || !profile.active || profile.id != userId) {
      throw const AccessFailure(
        'Account non abilitato o profilo non disponibile. Contatta l’amministratore.',
      );
    }
    return profile;
  }
}
