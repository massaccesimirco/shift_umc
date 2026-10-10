import '../models/planning.dart';

abstract interface class EmployeeRepository {
  Future<List<UserProfile>> list();
  Future<void> rename(String id, String firstName, String lastName);
  Future<void> setActive(String id, bool active);
}
