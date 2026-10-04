import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/demo_planning_repository.dart';
import '../models/planning.dart';
import '../repositories/planning_repository.dart';
import '../services/planning_service.dart';

final todayProvider = Provider<DateTime>((ref) => dateOnly(DateTime.now()));
final planningRepositoryProvider = Provider<PlanningRepository>(
  (ref) => DemoPlanningRepository(ref.watch(todayProvider)),
);
final planningServiceProvider = Provider(
  (ref) => PlanningService(ref.watch(planningRepositoryProvider)),
);
final selectedWeekProvider = NotifierProvider<SelectedWeek, DateTime>(
  SelectedWeek.new,
);

class SelectedWeek extends Notifier<DateTime> {
  @override
  DateTime build() => mondayOf(ref.watch(todayProvider));
  void move(int weeks) => state = addDays(state, weeks * 7);
  void reset() => state = mondayOf(ref.read(todayProvider));
}

final publishedWeekProvider = Provider(
  (ref) => ref
      .watch(planningServiceProvider)
      .publishedWeek(ref.watch(selectedWeekProvider)),
);
final weekAssignmentsProvider = Provider(
  (ref) => ref
      .watch(planningServiceProvider)
      .employeeAssignments(ref.watch(selectedWeekProvider)),
);
