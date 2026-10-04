import '../models/planning.dart';

abstract class AuthRepository {
  Stream<String?> get userIds;
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<UserProfile?> profileFor(String userId);
}
