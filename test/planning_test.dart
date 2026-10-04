import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_umc/app/app.dart';
import 'package:shift_umc/data/local/demo_planning_repository.dart';
import 'package:shift_umc/models/planning.dart';
import 'package:shift_umc/providers/planning_providers.dart';
import 'package:shift_umc/services/planning_service.dart';

void main() {
  final monday = DateTime(2026, 9, 21);
  test('Una bozza non è visibile al dipendente', () {
    final service = PlanningService(DemoPlanningRepository(monday));
    expect(service.publishedWeek(monday), isNotNull);
    expect(service.publishedWeek(addDays(monday, 7)), isNull);
    expect(service.employeeAssignments(addDays(monday, 7)), isEmpty);
  });
  test('Stati esclusivi, duplicati e attività multiple', () {
    final duties = DemoPlanningRepository(monday).duties;
    expect(PlanningService.validateDuties([duties[0], duties[1]]), isNull);
    expect(PlanningService.validateDuties([duties[0], duties[5]]), isNotNull);
    expect(PlanningService.validateDuties([duties[5]]), isNull);
    expect(PlanningService.validateDuties([duties[0], duties[0]]), isNotNull);
  });
  test('La settimana attraversa correttamente il cambio anno', () {
    expect(mondayOf(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets('Navigazione dipendente con larghezza $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [todayProvider.overrideWithValue(monday)],
          child: const ShiftUmcApp(demoMode: true),
        ),
      );
      expect(find.text('Sportello'), findsOneWidget);
      expect(find.text('Immatricolazioni'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'La mia settimana'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settimana successiva'));
      await tester.pumpAndSettle();
      expect(
        find.text('Nessuna pianificazione pubblicata per questa settimana.'),
        findsOneWidget,
      );
      expect(find.text('Sportello'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
