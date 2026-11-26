import '../models/published_planning.dart';

abstract interface class EmployeePlanningRepository {
  Future<PublishedPlanning?> load(DateTime monday, String employeeId);
}
