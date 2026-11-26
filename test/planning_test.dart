import 'package:flutter_test/flutter_test.dart';
import 'package:shift_umc/models/planning.dart';
import 'package:shift_umc/services/assignment_service.dart';

void main() {
  test(
    'Stati esclusivi, duplicati, mansioni disattivate e attività multiple',
    () {
      const activity = Duty(
        id: 'a',
        name: 'Sportello',
        type: DutyType.activity,
      );
      const other = Duty(id: 'b', name: 'Back Office', type: DutyType.activity);
      const holiday = Duty(
        id: 'h',
        name: 'Ferie',
        type: DutyType.status,
        exclusive: true,
      );
      const inactive = Duty(
        id: 'i',
        name: 'Vecchia mansione',
        type: DutyType.activity,
        active: false,
      );
      expect(AssignmentService.validateDuties([activity, other]), isNull);
      expect(AssignmentService.validateDuties([activity, holiday]), isNotNull);
      expect(AssignmentService.validateDuties([holiday]), isNull);
      expect(AssignmentService.validateDuties([activity, activity]), isNotNull);
      expect(AssignmentService.validateDuties([inactive]), isNotNull);
    },
  );

  test('La settimana attraversa correttamente il cambio anno', () {
    expect(mondayOf(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
  });
}
