import '../models/planning.dart';

abstract interface class EmployeeRepository {
  Future<List<UserProfile>> list();
  Future<void> create(
    String firstName,
    String lastName,
    String email,
    String password,
  );
  Future<void> rename(String id, String firstName, String lastName);
  Future<void> setActive(String id, bool active);
}
