import '../models/planning.dart';

abstract interface class AssignmentRepository {
  Future<List<Assignment>> list(String weekId);
  Future<void> saveSlot({
    required String weekId,
    required String employeeId,
    required DateTime date,
    required Period period,
    required List<String> dutyIds,
    required String notes,
    required List<Assignment> expected,
  });
}
