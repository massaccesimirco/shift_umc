enum UserRole { admin, employee }

enum DutyType { activity, status }

enum WeekStatus { draft, published }

enum Period { morning, afternoon }

class UserProfile {
  const UserProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    this.active = true,
  });
  final String id, firstName, lastName, email;
  final UserRole role;
  final bool active;
  String get fullName => '$firstName $lastName';
}

class Duty {
  const Duty({
    required this.id,
    required this.name,
    required this.type,
    this.exclusive = false,
    this.active = true,
  });
  final String id, name;
  final DutyType type;
  final bool exclusive, active;
}

class WeekPlan {
  const WeekPlan({
    required this.id,
    required this.startDate,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    this.publishedAt,
  });
  final String id, createdBy;
  final DateTime startDate, createdAt;
  final DateTime? publishedAt;
  final WeekStatus status;
}

class Assignment {
  const Assignment({
    required this.id,
    required this.weekPlanId,
    required this.employeeId,
    required this.date,
    required this.period,
    required this.dutyId,
    this.notes = '',
  });
  final String id, weekPlanId, employeeId, dutyId, notes;
  final DateTime date;
  final Period period;
}

// Tratto le date di pianificazione come giorni civili locali, senza orari di turno.
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
DateTime mondayOf(DateTime value) => DateTime(
  value.year,
  value.month,
  value.day - value.weekday + DateTime.monday,
);
DateTime addDays(DateTime value, int days) =>
    DateTime(value.year, value.month, value.day + days);
bool sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
