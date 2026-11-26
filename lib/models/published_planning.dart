import 'planning.dart';

class PublishedPlanning {
  const PublishedPlanning({
    required this.week,
    required this.assignments,
    required this.duties,
  });
  final WeekPlan week;
  final List<Assignment> assignments;
  final List<Duty> duties;
}
