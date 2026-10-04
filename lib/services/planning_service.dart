import '../models/planning.dart';
import '../repositories/planning_repository.dart';

class PlanningService {
  const PlanningService(this.repository);
  final PlanningRepository repository;

  // Questo filtro governa la UI. Con Supabase serviranno anche policy RLS:
  // un filtro nel client da solo non costituisce una protezione dei dati.
  WeekPlan? publishedWeek(DateTime date) {
    final week = repository.weekStarting(mondayOf(date));
    return week?.status == WeekStatus.published ? week : null;
  }

  List<Assignment> employeeAssignments(DateTime date) {
    final week = publishedWeek(date);
    if (week == null) return const [];
    return repository.assignmentsFor(week.id, repository.currentEmployee.id);
  }

  static String? validateDuties(List<Duty> duties) {
    if (duties.map((d) => d.id).toSet().length != duties.length) {
      return 'La stessa mansione non può essere assegnata due volte.';
    }
    if (duties.any((d) => !d.active)) {
      return 'Una mansione disattivata non è assegnabile.';
    }
    if (duties.length > 1 && duties.any((d) => d.exclusive)) {
      return 'Uno stato esclusivo deve essere assegnato da solo nella fascia.';
    }
    return null;
  }
}
