import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_umc/models/access_failure.dart';
import 'package:shift_umc/models/planning.dart';
import 'package:shift_umc/providers/assignment_providers.dart';
import 'package:shift_umc/providers/auth_providers.dart';
import 'package:shift_umc/providers/duty_providers.dart';
import 'package:shift_umc/providers/employee_providers.dart';
import 'package:shift_umc/presentation/screens/assignments_screen.dart';
import 'package:shift_umc/repositories/assignment_repository.dart';
import 'package:shift_umc/services/assignment_service.dart';

import 'auth_test.dart' show FakeAuthRepository, person;

class FakeAssignments implements AssignmentRepository {
  final rows = <Assignment>[];
  int writes = 0;
  Object? writeError, readError;
  Completer<void>? pending;
  List<Assignment>? receivedExpected;

  @override
  Future<List<Assignment>> list(String weekId) async {
    if (readError != null) throw readError!;
    return rows.where((a) => a.weekPlanId == weekId).toList();
  }

  @override
  Future<void> saveSlot({
    required String weekId,
    required String employeeId,
    required DateTime date,
    required Period period,
    required List<String> dutyIds,
    required String notes,
    required List<Assignment> expected,
  }) async {
    writes++;
    receivedExpected = expected;
    if (pending != null) await pending!.future;
    if (writeError != null) throw writeError!;
    rows.removeWhere(
      (a) =>
          a.weekPlanId == weekId &&
          a.employeeId == employeeId &&
          sameDate(a.date, date) &&
          a.period == period,
    );
    for (final id in dutyIds) {
      rows.add(
        Assignment(
          id: '$writes-$id',
          weekPlanId: weekId,
          employeeId: employeeId,
          date: date,
          period: period,
          dutyId: id,
          notes: notes,
        ),
      );
    }
  }
}

final monday = DateTime(2026, 11, 23);
WeekPlan plan({WeekStatus status = WeekStatus.draft}) => WeekPlan(
  id: 'week',
  startDate: monday,
  status: status,
  createdBy: 'user-1',
  createdAt: monday,
);
const sportello = Duty(
  id: 'sportello',
  name: 'Sportello',
  type: DutyType.activity,
);
const backOffice = Duty(
  id: 'back',
  name: 'Back Office',
  type: DutyType.activity,
);
const ferie = Duty(
  id: 'ferie',
  name: 'Ferie',
  type: DutyType.status,
  exclusive: true,
);
const inactive = Duty(
  id: 'old',
  name: 'Mansione disattivata',
  type: DutyType.activity,
  active: false,
);
final employee = person(id: 'employee', role: UserRole.employee);

void main() {
  Future<void> save(
    AssignmentService service, {
    WeekPlan? week,
    UserProfile? target,
    DateTime? date,
    List<Duty> duties = const [sportello],
    String notes = '',
    List<Assignment> expected = const [],
  }) => service.saveSlot(
    week: week ?? plan(),
    employee: target ?? employee,
    date: date ?? monday,
    period: Period.morning,
    duties: duties,
    notes: notes,
    expected: expected,
  );

  test('Rifiuto ruoli, stato pubblicato, date, duplicati e stati incompatibili prima della scrittura', () async {
    final repo = FakeAssignments();
    for (final actor in [
      person(role: UserRole.employee),
      person(active: false),
    ]) {
      final service = AssignmentService(repo, actor);
      await expectLater(save(service), throwsA(isA<AccessFailure>()));
      await expectLater(service.list('week'), throwsA(isA<AccessFailure>()));
    }
    final service = AssignmentService(repo, person());
    for (final attempt in [
      () => save(service, week: plan(status: WeekStatus.published)),
      () => save(service, date: addDays(monday, -1)),
      () => save(service, date: addDays(monday, 5)),
      () => save(service, target: person()),
      () =>
          save(service, target: person(role: UserRole.employee, active: false)),
      () => save(service, duties: [sportello, sportello]),
      () => save(service, duties: [ferie, sportello]),
      () => save(service, duties: [inactive]),
      () => save(service, notes: '😀' * 2001),
    ]) {
      await expectLater(attempt(), throwsA(isA<AccessFailure>()));
    }
    expect(repo.writes, 0);
  });

  test('Salvo più attività e note, mantengo la fotografia e posso svuotare un dipendente inattivo', () async {
    final repo = FakeAssignments();
    final service = AssignmentService(repo, person());
    await save(
      service,
      date: DateTime(2026, 11, 23, 18),
      duties: [sportello, backOffice],
      notes: ' Note ',
    );
    expect(repo.rows.length, 2);
    expect(repo.rows.first.notes, 'Note');
    expect(repo.rows.first.date, monday);
    final expected = [...repo.rows];
    await save(
      service,
      target: person(id: employee.id, role: UserRole.employee, active: false),
      duties: [],
      expected: expected,
    );
    expect(repo.rows, isEmpty);
    expect(repo.receivedExpected, expected);
  });

  Future<void> mount(WidgetTester tester, FakeAssignments repo) async {
    final auth = FakeAuthRepository()
      ..id = 'user-1'
      ..profile = person();
    addTearDown(auth.changes.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          assignmentRepositoryProvider.overrideWithValue(repo),
          employeesProvider('user-1').overrideWith((ref) async => [employee]),
          dutiesProvider('user-1').overrideWith(
            (ref) async => [sportello, backOffice, ferie, inactive],
          ),
        ],
        child: MaterialApp(
          home: AssignmentsScreen(userId: 'user-1', week: plan()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> edit(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Modifica mattina').first);
    await tester.tap(find.text('Modifica mattina').first);
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Salva fascia'));
    await tester.tap(find.text('Salva fascia'));
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'Salvo e rileggo le assegnazioni e poi svuoto la fascia a $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = FakeAssignments();
        await mount(tester, repo);
        await edit(tester);
        await tester.tap(find.text('Sportello'));
        await tester.tap(find.text('Back Office'));
        await tester.enterText(find.byType(TextField).last, 'Note di prova');
        await tapSave(tester);
        await tester.pumpAndSettle();
        expect(repo.rows.length, 2);
        expect(find.text('Sportello'), findsOneWidget);
        expect(find.text('Note di prova'), findsNWidgets(2));
        await edit(tester);
        await tester.tap(find.text('Svuota selezione'));
        await tapSave(tester);
        await tester.pumpAndSettle();
        expect(repo.rows, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Uno stato esclusivo combinato resta nel modulo senza scritture',
    (tester) async {
      final repo = FakeAssignments();
      await mount(tester, repo);
      await edit(tester);
      await tester.tap(find.text('Sportello'));
      await tester.tap(find.text('Ferie'));
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(repo.writes, 0);
      expect(
        find.text(
          'Uno stato esclusivo deve essere assegnato da solo nella fascia.',
        ),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets(
    'Errore concorrente mantiene il modulo e un invio pendente blocca il pulsante',
    (tester) async {
      final repo = FakeAssignments()
        ..pending = Completer<void>()
        ..writeError = const AccessFailure(
          'Fascia modificata da un altro amministratore.',
        );
      await mount(tester, repo);
      await edit(tester);
      await tester.tap(find.text('Sportello'));
      await tapSave(tester);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Salvataggio…'),
            )
            .onPressed,
        isNull,
      );
      expect(repo.writes, 1);
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('Fascia modificata da un altro amministratore.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Sportello'),
            )
            .value,
        isTrue,
      );
    },
  );

  testWidgets(
    'Una lettura fallita non mostra un editor vuoto e il retry recupera',
    (tester) async {
      final repo = FakeAssignments()..readError = Exception('errore interno');
      await mount(tester, repo);
      expect(find.text('Modifica mattina'), findsNothing);
      expect(find.textContaining('errore interno'), findsNothing);
      repo.readError = null;
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      expect(find.text('Modifica mattina'), findsWidgets);
    },
  );
}
