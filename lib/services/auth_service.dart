import '../models/access_failure.dart';
import '../models/password_rules.dart';
import '../models/planning.dart';
import '../repositories/auth_repository.dart';

class AuthService {
  const AuthService(this.repository);
  final AuthRepository repository;
  Future<void> signIn(String email, String password) =>
      repository.signIn(email.trim(), password);
  Future<void> signOut() => repository.signOut();
  Future<void> updatePassword(String userId, String password) async {
    await requireProfile(userId);
    final error = passwordError(password);
    if (error != null) throw AccessFailure(error);
    await repository.updatePassword(password);
  }

  Future<UserProfile> requireProfile(String userId) async {
    final profile = await repository.profileFor(userId);
    // Considero anche null come profilo non accessibile: le RLS nascondono i profili disattivati.
    if (profile == null || !profile.active || profile.id != userId) {
      throw const AccessFailure(
        'Account disattivato o non abilitato. Contatta l’amministratore.',
      );
    }
    return profile;
  }
}
