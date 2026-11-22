import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/access_failure.dart';
import '../../models/planning.dart';
import '../../repositories/duty_repository.dart';

class SupabaseDutyRepository implements DutyRepository {
  const SupabaseDutyRepository(this.client);
  final SupabaseClient client;

  @override
  Future<List<Duty>> list() async {
    final rows = await client
        .from('duty')
        .select('id,name,type,exclusive,active')
        .order('name');
    return rows
        .map(
          (row) => Duty(
            id: row['id'] as String,
            name: row['name'] as String,
            type: switch (row['type']) {
              'ACTIVITY' => DutyType.activity,
              'STATUS' => DutyType.status,
              _ => throw const AccessFailure(
                'Tipo di mansione non riconosciuto.',
              ),
            },
            exclusive: row['exclusive'] as bool,
            active: row['active'] as bool,
          ),
        )
        .toList();
  }

  Future<void> _write(Future<void> Function() operation) async {
    try {
      await operation();
    } on PostgrestException catch (error) {
      throw AccessFailure(switch (error.code) {
        '23505' => 'Esiste già una mansione con questo nome, anche tra quelle disattivate.',
        '23514' => 'Controlla il nome e il tipo: soltanto uno stato può essere esclusivo.',
        'P0001' => 'Questa mansione è già assegnata: tipo ed esclusività non possono cambiare. Crea una nuova mansione.',
        '42501' => 'Modifica non consentita. Verifica il ruolo e i permessi del database.',
        'PGRST116' => 'Mansione non disponibile o permessi cambiati. Aggiorna il profilo e riprova.',
        _ => 'Salvataggio non riuscito. Aggiorna l’elenco prima di riprovare.',
      });
    }
  }

  @override
  Future<void> save({
    String? id,
    required String name,
    required DutyType type,
    required bool exclusive,
  }) => _write(() async {
    final values = {
      'name': name,
      'type': type == DutyType.activity ? 'ACTIVITY' : 'STATUS',
      'exclusive': exclusive,
    };
    if (id == null) {
      await client.from('duty').insert(values).select('id').single();
    } else {
      await client
          .from('duty')
          .update(values)
          .eq('id', id)
          .select('id')
          .single();
    }
  });

  @override
  Future<void> setActive(String id, bool active) => _write(() async {
    await client
        .from('duty')
        .update({'active': active})
        .eq('id', id)
        .select('id')
        .single();
  });
}
