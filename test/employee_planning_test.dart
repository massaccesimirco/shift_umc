import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_umc/app/app.dart';
import 'package:shift_umc/models/access_failure.dart';
import 'package:shift_umc/models/planning.dart';
import 'package:shift_umc/models/published_planning.dart';
import 'package:shift_umc/providers/auth_providers.dart';
import 'package:shift_umc/providers/employee_planning_providers.dart';
import 'package:shift_umc/repositories/employee_planning_repository.dart';

import 'auth_test.dart' show FakeAuthRepository, person;

class FakePersonalPlanning implements EmployeePlanningRepository {
  int reads = 0;
  String? receivedId;
  Object? error;
  final weeks = <DateTime, PublishedPlanning>{};
  @override
  Future<PublishedPlanning?> load(DateTime monday, String employeeId) async {
    reads++;
    receivedId = employeeId;
    if (error != null) throw error!;
    return weeks[monday];
  }
}

void main() {
  final monday = DateTime(2026, 11, 23);
  PublishedPlanning data({
    String employeeId = 'user-1',
    WeekStatus status = WeekStatus.published,
  }) => PublishedPlanning(
    week: WeekPlan(
      id: 'week',
      startDate: monday,
      status: status,
      createdBy: 'admin',
      createdAt: monday,
      publishedAt: status == WeekStatus.published ? monday : null,
    ),
    assignments: [
      Assignment(
        id: 'row',
        weekPlanId: 'week',
        employeeId: employeeId,
        date: monday,
        period: Period.morning,
        dutyId: 'duty',
        notes: 'Presentarsi allo sportello',
      ),
    ],
    duties: const [
      Duty(id: 'duty', name: 'Sportello personale', type: DutyType.activity),
    ],
  );

  test('Il provider rifiuta bozze, dati di altri dipendenti e profili non autorizzati', () async {
    final auth = FakeAuthRepository()
      ..profile = person(role: UserRole.employee);
    addTearDown(auth.changes.close);
    final repo = FakePersonalPlanning();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        employeePlanningRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final provider = employeePlanningProvider((
      userId: 'user-1',
      monday: monday,
    ));
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    repo.weeks[monday] = data(status: WeekStatus.draft);
    await expectLater(
      container.read(provider.future),
      throwsA(isA<AccessFailure>()),
    );
    repo.weeks[monday] = data(employeeId: 'someone-else');
    container.invalidate(provider);
    await expectLater(
      container.read(provider.future),
      throwsA(isA<AccessFailure>()),
    );
    auth.profile = person();
    container.invalidate(currentProfileProvider('user-1'));
    final before = repo.reads;
    await expectLater(
      container.read(provider.future),
      throwsA(isA<AccessFailure>()),
    );
    expect(repo.reads, before);
  });

  Future<void> mount(
    WidgetTester tester,
    FakePersonalPlanning repo, {
    DateTime? today,
  }) async {
    final auth = FakeAuthRepository()
      ..id = 'user-1'
      ..profile = person(role: UserRole.employee);
    addTearDown(auth.changes.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          employeePlanningRepositoryProvider.overrideWithValue(repo),
          remoteTodayProvider.overrideWithValue(today ?? monday),
        ],
        child: const ShiftUmcApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('La mia pianificazione'));
    await tester.tap(find.text('La mia pianificazione'));
    await tester.pumpAndSettle();
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'Consulto dati reali, cambio settimana e faccio logout a $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = FakePersonalPlanning()..weeks[monday] = data();
        await mount(tester, repo);
        expect(repo.receivedId, 'user-1');
        expect(find.text('Sportello personale'), findsOneWidget);
        expect(find.text('Presentarsi allo sportello'), findsOneWidget);
        expect(
          width < 800
              ? find.byType(NavigationBar)
              : find.byType(NavigationRail),
          findsOneWidget,
        );
        await tester.tap(find.text('Settimana'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Settimana successiva'));
        await tester.pumpAndSettle();
        expect(
          find.text('Nessuna pianificazione pubblicata per questa settimana.'),
          findsOneWidget,
        );
        expect(find.text('Sportello personale'), findsNothing);
        await tester.tap(find.text('Esci'));
        await tester.pumpAndSettle();
        expect(find.text('Accedi al tuo ufficio'), findsOneWidget);
        expect(find.text('La mia settimana'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Un errore non diventa settimana vuota e Riprova rilegge il backend',
    (tester) async {
      final repo = FakePersonalPlanning()
        ..error = Exception('dettaglio tecnico');
      await mount(tester, repo);
      expect(
        find.text('Nessuna pianificazione pubblicata per questa settimana.'),
        findsNothing,
      );
      expect(find.textContaining('dettaglio tecnico'), findsNothing);
      repo.error = null;
      repo.weeks[monday] = data();
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      expect(find.text('Sportello personale'), findsOneWidget);
    },
  );

  testWidgets(
    'Nel fine settimana mostro un messaggio e consento la vista settimanale',
    (tester) async {
      final repo = FakePersonalPlanning()..weeks[monday] = data();
      await mount(tester, repo, today: addDays(monday, 5));
      expect(find.textContaining('Oggi è il fine settimana'), findsOneWidget);
      await tester.tap(find.text('Settimana'));
      await tester.pumpAndSettle();
      expect(find.text('Sportello personale'), findsOneWidget);
    },
  );
}
