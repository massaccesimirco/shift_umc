import '../models/planning.dart';

abstract class WeekRepository {
  Future<WeekPlan?> find(DateTime monday);
  Future<void> publish(String weekId, List<Assignment> expected);
  Future<WeekPlan> createDraft(DateTime monday, String createdBy);
}
