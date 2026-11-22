import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/access_failure.dart';
import '../../models/planning.dart';
import '../../repositories/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository(this.client);
  final SupabaseClient client;

  @override
  Stream<String?> get userIds =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (error) {
      throw AccessFailure(switch (error.code) {
        'invalid_credentials' => 'Email o password non corrette.',
        'email_not_confirmed' => 'Conferma la tua email prima di accedere.',
        'over_request_rate_limit' =>
          'Troppi tentativi. Attendi prima di riprovare.',
        _ => 'Accesso non riuscito. Controlla i dati e riprova.',
      });
    }
  }

  @override
  Future<void> updatePassword(String password) async {
    try {
      await client.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (error) {
      throw AccessFailure(switch (error.code) {
        'weak_password' => 'Scegli una password più robusta, conforme ai requisiti del servizio.',
        'same_password' =>
          'La nuova password deve essere diversa da quella attuale.',
        'reauthentication_needed' =>
          'Esci e accedi di nuovo prima di cambiare la password.',
        _ => 'Password non modificata. Verifica la sessione e riprova.',
      });
    }
  }

  @override
  Future<void> signOut() => client.auth.signOut(scope: SignOutScope.local);

  @override
  Future<UserProfile?> profileFor(String userId) async {
    final row = await client
        .from('user_profile')
        .select('id, first_name, last_name, email, role, active')
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return null;
    return UserProfile(
      id: row['id'] as String,
      firstName: row['first_name'] as String,
      lastName: row['last_name'] as String,
      email: row['email'] as String,
      role: switch (row['role']) {
        'ADMIN' => UserRole.admin,
        'EMPLOYEE' => UserRole.employee,
        _ => throw const AccessFailure(
          'Il ruolo del tuo account non è riconosciuto.',
        ),
      },
      active: row['active'] as bool,
    );
  }
}
