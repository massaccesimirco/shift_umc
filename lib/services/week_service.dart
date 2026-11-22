import '../models/access_failure.dart';
import '../models/planning.dart';
import '../repositories/week_repository.dart';

class WeekService {
  const WeekService(this.repository, this.actor);
  final WeekRepository repository;
  final UserProfile actor;

  DateTime _validate(DateTime monday) {
    if (!actor.active || actor.role != UserRole.admin) {
      throw const AccessFailure(
        'Operazione riservata agli amministratori attivi.',
      );
    }
    if (monday.weekday != DateTime.monday) {
      throw const AccessFailure('La settimana deve iniziare di lunedì.');
    }
    return dateOnly(monday);
  }

  Future<WeekPlan?> find(DateTime monday) async =>
      repository.find(_validate(monday));
  Future<WeekPlan> createDraft(DateTime monday) async =>
      repository.createDraft(_validate(monday), actor.id);
}
