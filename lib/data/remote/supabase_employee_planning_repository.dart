import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/access_failure.dart';
import '../../models/planning.dart';
import '../../models/published_planning.dart';
import '../../repositories/employee_planning_repository.dart';

class SupabaseEmployeePlanningRepository implements EmployeePlanningRepository {
  const SupabaseEmployeePlanningRepository(this.client);
  final SupabaseClient client;

  @override
  Future<PublishedPlanning?> load(DateTime monday, String employeeId) async {
    final day =
        '${monday.year.toString().padLeft(4, '0')}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
    final row = await client
        .from('week_plan')
        .select('id,start_date,status,created_by,created_at,published_at')
        .eq('start_date', day)
        .eq('status', 'PUBLISHED')
        .maybeSingle();
    if (row == null) return null;
    final week = WeekPlan(
      id: row['id'] as String,
      startDate: DateTime.parse(row['start_date'] as String),
      status: WeekStatus.published,
      createdBy: row['created_by'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      publishedAt: DateTime.parse(row['published_at'] as String),
    );
    // Chiedo solo le righe personali; le RLS controllano comunque l'identità sul server.
    final rows = await client
        .from('assignment')
        .select(
          'id,week_plan_id,employee_id,date,period,duty_id,notes,duty(id,name,type,exclusive,active)',
        )
        .eq('week_plan_id', week.id)
        .eq('employee_id', employeeId)
        .order('date')
        .order('duty_id');
    final assignments = <Assignment>[];
    final duties = <String, Duty>{};
    for (final item in rows) {
      final d = item['duty'] as Map<String, dynamic>?;
      if (d == null) {
        throw const AccessFailure(
          'Mansione non disponibile. Aggiorna la pianificazione.',
        );
      }
      duties[d['id'] as String] = Duty(
        id: d['id'] as String,
        name: d['name'] as String,
        type: switch (d['type']) {
          'ACTIVITY' => DutyType.activity,
          'STATUS' => DutyType.status,
          _ => throw const AccessFailure('Tipo di mansione non riconosciuto.'),
        },
        exclusive: d['exclusive'] as bool,
        active: d['active'] as bool,
      );
      assignments.add(
        Assignment(
          id: item['id'] as String,
          weekPlanId: week.id,
          employeeId: item['employee_id'] as String,
          date: DateTime.parse(item['date'] as String),
          period: switch (item['period']) {
            'MORNING' => Period.morning,
            'AFTERNOON' => Period.afternoon,
            _ => throw const AccessFailure('Fascia non riconosciuta.'),
          },
          dutyId: item['duty_id'] as String,
          notes: item['notes'] as String,
        ),
      );
    }
    return PublishedPlanning(
      week: week,
      assignments: assignments,
      duties: duties.values.toList(),
    );
  }
}
