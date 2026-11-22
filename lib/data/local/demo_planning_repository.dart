import '../../models/planning.dart';
import '../../repositories/planning_repository.dart';

// Uso questa sorgente in memoria per studiare e verificare il flusso della demo.
class DemoPlanningRepository implements PlanningRepository {
  DemoPlanningRepository(DateTime today) {
    final monday = mondayOf(today);
    _weeks = List.generate(3, (index) {
      final start = addDays(monday, (index - 1) * 7);
      return WeekPlan(
        id: 'week-$index',
        startDate: start,
        status: index == 2 ? WeekStatus.draft : WeekStatus.published,
        createdBy: 'demo-admin',
        createdAt: addDays(start, -7),
        publishedAt: index == 2 ? null : addDays(start, -3),
      );
    });
    _assignments = [
      for (final week in _weeks) ...[
        for (var day = 0; day < 5; day++) ...[
          Assignment(
            id: '${week.id}-$day-am',
            weekPlanId: week.id,
            employeeId: currentEmployee.id,
            date: addDays(week.startDate, day),
            period: Period.morning,
            dutyId: day.isEven ? 'sportello' : 'revisioni',
          ),
          if (day == 0)
            Assignment(
              id: '${week.id}-$day-extra',
              weekPlanId: week.id,
              employeeId: currentEmployee.id,
              date: addDays(week.startDate, day),
              period: Period.morning,
              dutyId: 'immatricolazioni',
            ),
          Assignment(
            id: '${week.id}-$day-pm',
            weekPlanId: week.id,
            employeeId: currentEmployee.id,
            date: addDays(week.startDate, day),
            period: Period.afternoon,
            dutyId: day == 3 ? 'smart' : 'back-office',
            notes: day == 0 ? 'Verifica delle pratiche in sospeso.' : '',
          ),
        ],
      ],
    ];
  }
  late final List<WeekPlan> _weeks;
  late final List<Assignment> _assignments;
  @override
  final currentEmployee = const UserProfile(
    id: 'demo-mario',
    firstName: 'Mario',
    lastName: 'Rossi',
    email: 'mario@example.invalid',
    role: UserRole.employee,
  );
  @override
  final List<Duty> duties = const [
    Duty(id: 'sportello', name: 'Sportello', type: DutyType.activity),
    Duty(id: 'revisioni', name: 'Revisioni', type: DutyType.activity),
    Duty(
      id: 'immatricolazioni',
      name: 'Immatricolazioni',
      type: DutyType.activity,
    ),
    Duty(id: 'back-office', name: 'Back Office', type: DutyType.activity),
    Duty(id: 'smart', name: 'Smart Working', type: DutyType.status),
    Duty(id: 'ferie', name: 'Ferie', type: DutyType.status, exclusive: true),
    Duty(
      id: 'assente',
      name: 'Assente',
      type: DutyType.status,
      exclusive: true,
    ),
  ];
  @override
  WeekPlan? weekStarting(DateTime monday) {
    for (final week in _weeks) {
      if (sameDate(week.startDate, monday)) return week;
    }
    return null;
  }

  @override
  List<Assignment> assignmentsFor(String weekId, String employeeId) =>
      _assignments
          .where((a) => a.weekPlanId == weekId && a.employeeId == employeeId)
          .toList(growable: false);
}
