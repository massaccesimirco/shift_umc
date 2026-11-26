import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/access_failure.dart';
import '../../models/planning.dart';
import '../../repositories/week_repository.dart';

class SupabaseWeekRepository implements WeekRepository {
  const SupabaseWeekRepository(this.client);
  final SupabaseClient client;
  static const _columns =
      'id,start_date,status,created_by,created_at,published_at';

  // Invio a PostgreSQL DATE il giorno civile, senza convertirlo in UTC.
  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  WeekPlan _decode(Map<String, dynamic> row) => WeekPlan(
    id: row['id'] as String,
    startDate: DateTime.parse(row['start_date'] as String),
    status: switch (row['status']) {
      'DRAFT' => WeekStatus.draft,
      'PUBLISHED' => WeekStatus.published,
      _ => throw const AccessFailure('Stato della settimana non riconosciuto.'),
    },
    createdBy: row['created_by'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    publishedAt: row['published_at'] == null
        ? null
        : DateTime.parse(row['published_at'] as String),
  );

  @override
  Future<void> publish(String weekId, List<Assignment> expected) async {
    final snapshot = [...expected]..sort((a, b) => a.id.compareTo(b.id));
    try {
      await client.rpc(
        'publish_week',
        params: {
          'p_week_id': weekId,
          'p_expected': snapshot
              .map((a) => {'id': a.id, 'notes': a.notes})
              .toList(),
        },
      );
    } on PostgrestException catch (error) {
      throw AccessFailure(switch (error.message) {
        'publication_empty' =>
          'Assegna almeno una mansione prima di pubblicare.',
        'publication_conflict' =>
          'La bozza è cambiata. Controlla le assegnazioni e riprova.',
        'publication_invalid_assignments' => 'Controlla le assegnazioni: dipendenti e mansioni devono essere attivi e le fasce valide.',
        'publication_week_missing' =>
          'Settimana non disponibile. Aggiorna l’elenco.',
        _ => switch (error.code) {
          '42501' => 'Pubblicazione riservata agli amministratori attivi.',
          'PGRST202' => 'Pubblicazione non configurata: applica la migrazione 007 su Supabase.',
          _ => 'Pubblicazione non confermata. Aggiorna le settimane prima di riprovare.',
        },
      });
    }
  }

  @override
  Future<WeekPlan?> find(DateTime monday) async {
    final row = await client
        .from('week_plan')
        .select(_columns)
        .eq('start_date', _date(monday))
        .maybeSingle();
    return row == null ? null : _decode(row);
  }

  @override
  Future<WeekPlan> createDraft(DateTime monday, String createdBy) async {
    try {
      final row = await client
          .from('week_plan')
          .insert({'start_date': _date(monday), 'created_by': createdBy})
          .select(_columns)
          .single();
      return _decode(row);
    } on PostgrestException catch (error) {
      throw AccessFailure(switch (error.code) {
        '23505' => 'Questa settimana esiste già. Premi Aggiorna per aprirla.',
        '23514' => 'La settimana deve iniziare di lunedì.',
        '42501' => 'Creazione non consentita. Verifica il ruolo e i permessi del database.',
        _ => 'Creazione non riuscita. Premi Aggiorna prima di riprovare.',
      });
    }
  }
}
