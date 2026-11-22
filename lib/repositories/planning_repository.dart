import '../models/planning.dart';

abstract class PlanningRepository {
  UserProfile get currentEmployee;
  List<Duty> get duties;
  WeekPlan? weekStarting(DateTime monday);
  List<Assignment> assignmentsFor(String weekId, String employeeId);
}
