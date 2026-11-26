import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/access_failure.dart';
import '../../models/planning.dart';
import '../../repositories/assignment_repository.dart';

class SupabaseAssignmentRepository implements AssignmentRepository {
  const SupabaseAssignmentRepository(this.client);
  final SupabaseClient client;

  @override
  Future<List<Assignment>> list(String weekId) async {
    final rows = await client
        .from('assignment')
        .select('id,week_plan_id,employee_id,date,period,duty_id,notes')
        .eq('week_plan_id', weekId)
        .order('date')
        .order('duty_id');
    return rows
        .map(
          (row) => Assignment(
            id: row['id'] as String,
            weekPlanId: row['week_plan_id'] as String,
            employeeId: row['employee_id'] as String,
            date: DateTime.parse(row['date'] as String),
            period: switch (row['period']) {
              'MORNING' => Period.morning,
              'AFTERNOON' => Period.afternoon,
              _ => throw const AccessFailure('Fascia non riconosciuta.'),
            },
            dutyId: row['duty_id'] as String,
            notes: row['notes'] as String,
          ),
        )
        .toList();
  }

  @override
  Future<void> saveSlot({
    required String weekId,
    required String employeeId,
    required DateTime date,
    required Period period,
    required List<String> dutyIds,
    required String notes,
    required List<Assignment> expected,
  }) async {
    // Ordino la fotografia letta come il database per confrontare la stessa fascia.
    final snapshot = [...expected]
      ..sort((a, b) => a.dutyId.compareTo(b.dutyId));
    final day =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    try {
      await client.rpc(
        'save_assignment_slot',
        params: {
          'p_week_id': weekId,
          'p_employee_id': employeeId,
          'p_date': day,
          'p_period': period == Period.morning ? 'MORNING' : 'AFTERNOON',
          'p_duty_ids': dutyIds,
          'p_notes': notes,
          'p_expected': snapshot
              .map((a) => {'duty_id': a.dutyId, 'notes': a.notes})
              .toList(),
        },
      );
    } on PostgrestException catch (error) {
      throw AccessFailure(switch (error.message) {
        'assignment_conflict' => 'Questa fascia è stata modificata. Chiudi il modulo e aggiorna le assegnazioni prima di riprovare.',
        'assignment_week_not_draft' =>
          'La settimana non è più una bozza. Aggiorna le settimane.',
        'assignment_employee_unavailable' =>
          'Il dipendente non è più disponibile. Aggiorna le assegnazioni.',
        'assignment_duty_unavailable' =>
          'Una mansione non è più disponibile. Aggiorna le assegnazioni.',
        'assignment_exclusive_conflict' =>
          'Uno stato esclusivo deve essere assegnato da solo nella fascia.',
        _ => switch (error.code) {
          '42501' => 'Salvataggio non consentito. Verifica il profilo.',
          '22023' => 'Controlla giorno, mansioni e note.',
          'PGRST202' => 'Gestione assegnazioni non configurata: applica la migrazione 006 su Supabase.',
          _ => 'Salvataggio non riuscito. Aggiorna le assegnazioni prima di riprovare.',
        },
      });
    }
  }
}
