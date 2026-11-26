import '../models/access_failure.dart';
import '../models/planning.dart';
import '../repositories/assignment_repository.dart';

class AssignmentService {
  const AssignmentService(this.repository, this.actor);
  final AssignmentRepository repository;
  final UserProfile actor;

  void _requireAdmin() {
    if (!actor.active || actor.role != UserRole.admin) {
      throw const AccessFailure(
        'Operazione riservata agli amministratori attivi.',
      );
    }
  }

  Future<List<Assignment>> list(String weekId) async {
    _requireAdmin();
    return repository.list(weekId);
  }

  Future<void> saveSlot({
    required WeekPlan week,
    required UserProfile employee,
    required DateTime date,
    required Period period,
    required List<Duty> duties,
    required String notes,
    required List<Assignment> expected,
  }) async {
    _requireAdmin();
    final day = dateOnly(date);
    if (week.status != WeekStatus.draft) {
      throw const AccessFailure(
        'Puoi modificare soltanto una settimana in bozza.',
      );
    }
    if (day.isBefore(dateOnly(week.startDate)) ||
        day.isAfter(addDays(week.startDate, 4))) {
      throw const AccessFailure('Scegli un giorno lavorativo della settimana.');
    }
    // Consento di svuotare la fascia anche dopo la disattivazione del dipendente.
    if (employee.role != UserRole.employee ||
        (!employee.active && duties.isNotEmpty)) {
      throw const AccessFailure(
        'Il dipendente non è disponibile per nuove assegnazioni.',
      );
    }
    final error = validateDuties(duties);
    if (error != null) throw AccessFailure(error);
    if (duties.length > 100 || notes.runes.length > 2000) {
      throw const AccessFailure(
        'Usa al massimo 100 mansioni e 2000 caratteri di note.',
      );
    }
    await repository.saveSlot(
      weekId: week.id,
      employeeId: employee.id,
      date: day,
      period: period,
      dutyIds: duties.map((d) => d.id).toList(),
      notes: notes.trim(),
      expected: expected,
    );
  }

  // Ricontrollo le mansioni nel servizio prima di inviare la fascia al database.
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
