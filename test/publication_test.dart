import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_umc/models/access_failure.dart';
import 'package:shift_umc/models/planning.dart';
import 'package:shift_umc/presentation/screens/weeks_panel.dart';
import 'package:shift_umc/providers/auth_providers.dart';
import 'package:shift_umc/providers/assignment_providers.dart';
import 'package:shift_umc/providers/week_providers.dart';
import 'package:shift_umc/services/week_service.dart';

import 'auth_test.dart' show FakeAuthRepository, person;
import 'weeks_test.dart' show FakeWeeks;
import 'assignments_test.dart' show FakeAssignments;

void main() {
  final monday = mondayOf(DateTime.now());
  WeekPlan plan() => WeekPlan(
    id: 'week',
    startDate: monday,
    status: WeekStatus.draft,
    createdBy: 'user-1',
    createdAt: monday,
  );
  Assignment assignment() => Assignment(
    id: 'row',
    weekPlanId: 'week',
    employeeId: 'employee',
    date: monday,
    period: Period.morning,
    dutyId: 'duty',
  );

  test('Pubblicazione riservata ad admin attivi e bozze non vuote', () async {
    final repo = FakeWeeks()..rows[monday] = plan();
    for (final actor in [
      person(role: UserRole.employee),
      person(active: false),
    ]) {
      await expectLater(
        WeekService(repo, actor).publish(plan(), [assignment()]),
        throwsA(isA<AccessFailure>()),
      );
    }
    await expectLater(
      WeekService(repo, person()).publish(plan(), []),
      throwsA(isA<AccessFailure>()),
    );
    expect(repo.writes, 0);
    await WeekService(repo, person()).publish(plan(), [assignment()]);
    expect(repo.rows[monday]!.status, WeekStatus.published);
    expect(repo.rows[monday]!.publishedAt, isNotNull);
  });

  Future<void> mount(
    WidgetTester tester,
    FakeWeeks weeks,
    FakeAssignments assignments,
  ) async {
    final auth = FakeAuthRepository()
      ..id = 'user-1'
      ..profile = person();
    addTearDown(auth.changes.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          weekRepositoryProvider.overrideWithValue(weeks),
          assignmentRepositoryProvider.overrideWithValue(assignments),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeeksPanel(userId: 'user-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openConfirmation(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Pubblica settimana'));
    await tester.tap(find.text('Pubblica settimana'));
    await tester.pumpAndSettle();
  }

  testWidgets('Una bozza vuota non apre la conferma e non viene pubblicata', (
    tester,
  ) async {
    final weeks = FakeWeeks()..rows[monday] = plan();
    await mount(tester, weeks, FakeAssignments());
    await openConfirmation(tester);
    expect(
      find.text('Assegna almeno una mansione prima di pubblicare.'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(weeks.writes, 0);
  });

  testWidgets(
    'Annullare conserva la bozza, confermare pubblica e toglie la modifica',
    (tester) async {
      final weeks = FakeWeeks()..rows[monday] = plan();
      final assignments = FakeAssignments()..rows.add(assignment());
      await mount(tester, weeks, assignments);
      await openConfirmation(tester);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(weeks.writes, 0);
      await openConfirmation(tester);
      await tester.tap(find.text('Conferma pubblicazione'));
      await tester.pumpAndSettle();
      expect(weeks.rows[monday]!.status, WeekStatus.published);
      expect(find.text('Gestisci assegnazioni'), findsNothing);
      expect(find.text('Pubblica settimana'), findsNothing);
      expect(find.text('Consulta assegnazioni'), findsOneWidget);
    },
  );

  testWidgets(
    'Errore di pubblicazione mantiene la bozza e blocca invii mentre attendo',
    (tester) async {
      final weeks = FakeWeeks()
        ..rows[monday] = plan()
        ..pending = Completer<void>()
        ..writeError = const AccessFailure('La bozza è cambiata.');
      await mount(tester, weeks, FakeAssignments()..rows.add(assignment()));
      await openConfirmation(tester);
      await tester.tap(find.text('Conferma pubblicazione'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Operazione in corso…'),
            )
            .onPressed,
        isNull,
      );
      expect(weeks.writes, 1);
      weeks.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('La bozza è cambiata.'), findsOneWidget);
      expect(weeks.rows[monday]!.status, WeekStatus.draft);
    },
  );
}
