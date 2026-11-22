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
