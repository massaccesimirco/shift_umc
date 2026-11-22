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

  @override
  Future<void> create(
    String firstName,
    String lastName,
    String email,
    String password,
  ) async {
    try {
      await client.functions.invoke(
        'create-employee',
        body: {
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
          'password': password,
        },
      );
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['code'] : null;
      throw AccessFailure(switch (code) {
        'invalid_input' =>
          'Controlla nome, cognome, email e password.',
        'email_exists' => 'Esiste già un account con questa email. Controlla anche i dipendenti disattivati.',
        'weak_password' => 'La password non rispetta i requisiti del servizio. Scegline una più robusta.',
        'forbidden' => 'Operazione riservata agli amministratori attivi.',
        'unauthorized' => 'Sessione scaduta. Esci e accedi di nuovo.',
        _ => 'Creazione non riuscita. Aggiorna l’elenco prima di riprovare; se il problema continua, verifica la configurazione del servizio.',
      });
    }
  }

  Future<void> _update(String id, Map<String, dynamic> values) async {
    try {
      // Richiedo la riga modificata per verificare il salvataggio: con le RLS
      // potrei altrimenti aggiornare zero righe senza ricevere un errore SQL.
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
