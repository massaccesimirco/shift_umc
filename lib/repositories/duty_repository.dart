import '../models/planning.dart';

abstract interface class DutyRepository {
  Future<List<Duty>> list();
  Future<void> save({
    String? id,
    required String name,
    required DutyType type,
    required bool exclusive,
  });
  Future<void> setActive(String id, bool active);
}
