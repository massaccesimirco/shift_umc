import '../models/access_failure.dart';
import '../models/planning.dart';
import '../repositories/employee_repository.dart';

class EmployeeService {
  const EmployeeService(this.repository, this.actor);
  final EmployeeRepository repository;
  final UserProfile actor;

  void _requireAdmin() {
    if (!actor.active || actor.role != UserRole.admin) {
      throw const AccessFailure(
        'Operazione riservata agli amministratori attivi.',
      );
    }
  }

  void _requireEmployee(UserProfile employee) {
    _requireAdmin();
    if (employee.role != UserRole.employee || employee.id == actor.id) {
      throw const AccessFailure(
        'Questa schermata gestisce soltanto i dipendenti.',
      );
    }
  }

  Future<List<UserProfile>> list() async {
    _requireAdmin();
    return repository.list();
  }

  Future<void> rename(
    UserProfile employee,
    String firstName,
    String lastName,
  ) async {
    _requireEmployee(employee);
    final first = firstName.trim();
    final last = lastName.trim();
    if ([
      first,
      last,
    ].any((value) => value.isEmpty || value.runes.length > 120)) {
      throw const AccessFailure(
        'Nome e cognome devono contenere da 1 a 120 caratteri.',
      );
    }
    await repository.rename(employee.id, first, last);
  }

  Future<void> setActive(UserProfile employee, bool active) async {
    _requireEmployee(employee);
    await repository.setActive(employee.id, active);
  }
}
