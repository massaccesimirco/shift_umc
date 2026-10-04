import '../models/access_failure.dart';
import '../models/planning.dart';
import '../repositories/duty_repository.dart';

class DutyService {
  const DutyService(this.repository, this.profile);
  final DutyRepository repository;
  final UserProfile profile;

  void _requireAdmin() {
    if (!profile.active || profile.role != UserRole.admin) {
      throw const AccessFailure(
        'Operazione riservata agli amministratori attivi.',
      );
    }
  }

  Future<void> save({
    String? id,
    required String name,
    required DutyType type,
    required bool exclusive,
  }) async {
    _requireAdmin();
    final cleaned = name.trim();
    if (cleaned.isEmpty || cleaned.runes.length > 120) {
      throw const AccessFailure('Inserisci un nome da 1 a 120 caratteri.');
    }
    if (exclusive && type != DutyType.status) {
      throw const AccessFailure('Solo uno stato può essere esclusivo.');
    }
    await repository.save(
      id: id,
      name: cleaned,
      type: type,
      exclusive: exclusive,
    );
  }

  Future<void> setActive(String id, bool active) async {
    _requireAdmin();
    await repository.setActive(id, active);
  }
}
