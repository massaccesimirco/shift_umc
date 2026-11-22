import '../models/planning.dart';

abstract class WeekRepository {
  Future<WeekPlan?> find(DateTime monday);
  Future<WeekPlan> createDraft(DateTime monday, String createdBy);
}
