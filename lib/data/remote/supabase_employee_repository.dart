import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/access_failure.dart';
import '../../models/planning.dart';
import '../../repositories/employee_repository.dart';

class SupabaseEmployeeRepository implements EmployeeRepository {
  const SupabaseEmployeeRepository(this.client);
  final SupabaseClient client;

  @override
  Future<List<UserProfile>> list() async {
    final rows = await client
        .from('user_profile')
        .select('id,first_name,last_name,email,role,active')
        .eq('role', 'EMPLOYEE')
        .order('last_name')
        .order('first_name')
        .order('id');
    return rows
        .map(
          (row) => UserProfile(
            id: row['id'] as String,
            firstName: row['first_name'] as String,
            lastName: row['last_name'] as String,
            email: row['email'] as String,
            role: UserRole.employee,
            active: row['active'] as bool,
          ),
        )
        .toList();
  }

  Future<void> _update(String id, Map<String, dynamic> values) async {
    try {
      // La risposta conferma che una riga è stata modificata: le RLS possono
      // altrimenti produrre un update di zero righe senza un errore SQL.
      await client
          .from('user_profile')
          .update(values)
          .eq('id', id)
          .eq('role', 'EMPLOYEE')
          .select('id')
          .single();
    } on PostgrestException catch (error) {
      throw AccessFailure(switch (error.code) {
        '23514' => 'Nome e cognome devono contenere da 1 a 120 caratteri.',
        '42501' => 'Modifica non consentita. Verifica il ruolo e i permessi del database.',
        'PGRST116' => 'Dipendente non disponibile o permessi cambiati. Aggiorna il profilo e riprova.',
        _ => 'Salvataggio non riuscito. Aggiorna l’elenco prima di riprovare.',
      });
    }
  }

  @override
  Future<void> rename(String id, String firstName, String lastName) =>
      _update(id, {'first_name': firstName, 'last_name': lastName});
  @override
  Future<void> setActive(String id, bool active) =>
      _update(id, {'active': active});
}
