import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_umc/app/app.dart';
import 'package:shift_umc/data/local/local_planning_store.dart';
import 'package:shift_umc/models/access_failure.dart';
import 'package:shift_umc/models/planning.dart';
import 'package:shift_umc/models/published_planning.dart';
import 'package:shift_umc/providers/auth_providers.dart';
import 'package:shift_umc/providers/employee_planning_providers.dart';
import 'package:shift_umc/providers/local_planning_providers.dart';

import 'auth_test.dart' show FakeAuthRepository, person;
import 'employee_planning_test.dart' show FakePersonalPlanning;

final monday = DateTime(2026, 11, 23);
PublishedPlanning personal({
  String userId = 'user-1',
  DateTime? start,
  String notes = 'Nota personale',
  WeekStatus status = WeekStatus.published,
}) {
  final date = start ?? monday;
  final id = 'week-${date.toIso8601String()}';
  return PublishedPlanning(
    week: WeekPlan(
      id: id,
      startDate: date,
      status: status,
      createdBy: 'admin',
      createdAt: date,
      publishedAt: status == WeekStatus.published ? date : null,
    ),
    assignments: [
      Assignment(
        id: 'assignment',
        weekPlanId: id,
        employeeId: userId,
        date: date,
        period: Period.morning,
        dutyId: 'duty',
        notes: notes,
      ),
    ],
    duties: const [
      Duty(id: 'duty', name: 'Sportello salvato', type: DutyType.activity),
    ],
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Rileggo dopo aver ricreato lo storage e separo i dati dei due account',
    () async {
      final savedAt = DateTime(2026, 11, 26, 10, 30);
      final first = LocalPlanningStore(now: () => savedAt);
      await first.save('user-1', personal(), first.generation('user-1'));
      await first.save(
        'user-2',
        personal(userId: 'user-2', notes: 'Secondo account'),
        first.generation('user-2'),
      );
      final reopened = LocalPlanningStore();
      final copy = await reopened.read('user-1', monday);
      expect(copy!.savedAt, savedAt);
      expect(copy.planning.assignments.single.notes, 'Nota personale');
      expect(copy.planning.duties.single.name, 'Sportello salvato');
      expect(copy.planning.week.status, WeekStatus.published);
      expect(
        (await reopened.read(
          'user-2',
          monday,
        ))!.planning.assignments.single.notes,
        'Secondo account',
      );
      expect(await reopened.read('user-3', monday), isNull);
      await reopened.clearUser('user-1');
      expect(await LocalPlanningStore().read('user-1', monday), isNull);
      expect(await reopened.read('user-2', monday), isNotNull);
    },
  );

  test(
    'Non salvo bozze o assegnazioni di altri account e ignoro cache corrotte',
    () async {
      final store = LocalPlanningStore();
      await expectLater(
        store.save('user-1', personal(status: WeekStatus.draft), 0),
        throwsFormatException,
      );
      await expectLater(
        store.save('user-1', personal(userId: 'other'), 0),
        throwsFormatException,
      );
      final prefs = await SharedPreferences.getInstance();
      for (final raw in [
        'JSON non valido',
        jsonEncode({'version': 99, 'user_id': 'user-1', 'weeks': []}),
        jsonEncode({'version': 1, 'user_id': 'another-user', 'weeks': []}),
      ]) {
        await prefs.setString('shiftumc.planning.v1.user-1', raw);
        expect(await store.readAll('user-1'), isEmpty);
      }
    },
  );

  test('Mantengo le otto settimane più recenti e aggiorno la stessa senza duplicarla', () async {
    var clock = DateTime(2026, 11, 26);
    final store = LocalPlanningStore(
      now: () {
        clock = clock.add(const Duration(seconds: 1));
        return clock;
      },
    );
    for (var i = 0; i < 10; i++) {
      await store.save('user-1', personal(start: addDays(monday, i * 7)), 0);
    }
    expect((await store.readAll('user-1')).length, 8);
    expect(await store.read('user-1', monday), isNull);
    final selected = addDays(monday, 9 * 7);
    await store.save(
      'user-1',
      personal(start: selected, notes: 'Aggiornata'),
      0,
    );
    expect((await store.readAll('user-1')).length, 8);
    expect(
      (await store.read('user-1', selected))!.planning.assignments.single.notes,
      'Aggiornata',
    );
    await store.removeWeek('user-1', selected, 0);
    expect(await store.read('user-1', selected), isNull);
  });

  test('Un salvataggio tardivo non ricrea la copia dopo il logout', () async {
    final prefs = await SharedPreferences.getInstance();
    final pending = Completer<SharedPreferences>();
    final store = LocalPlanningStore(preferences: () => pending.future);
    final write = store.save('user-1', personal(), 0);
    await Future<void>.delayed(Duration.zero);
    final logout = store.clearUser('user-1');
    pending.complete(prefs);
    expect(await write, isNull);
    await logout;
    expect(await store.save('user-1', personal(), 0), isNull);
    expect(await store.readAll('user-1'), isEmpty);
  });

  ProviderContainer containerFor(
    FakeAuthRepository auth,
    FakePersonalPlanning repo,
    LocalPlanningStore store,
  ) => ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      employeePlanningRepositoryProvider.overrideWithValue(repo),
      localPlanningStoreProvider.overrideWithValue(store),
    ],
  );

  test('Prima leggo online, poi uso la copia su errore di rete, ma non per altri errori', () async {
    final auth = FakeAuthRepository()
      ..profile = person(role: UserRole.employee);
    addTearDown(auth.changes.close);
    final repo = FakePersonalPlanning()..weeks[monday] = personal();
    final store = LocalPlanningStore();
    final container = containerFor(auth, repo, store);
    addTearDown(container.dispose);
    final provider = employeePlanningProvider((
      userId: 'user-1',
      monday: monday,
    ));
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    final online = await container.read(provider.future);
    expect(online.fromCache, isFalse);
    expect(online.savedAt, isNotNull);
    repo.error = ClientException('offline');
    container.invalidate(provider);
    final offline = await container.read(provider.future);
    expect(offline.fromCache, isTrue);
    expect(offline.savedAt, online.savedAt);
    expect(offline.planning!.assignments.single.notes, 'Nota personale');
    repo.error = StateError('risposta non valida');
    container.invalidate(provider);
    await expectLater(container.read(provider.future), throwsStateError);
    repo.error = const AccessFailure('Accesso non consentito.');
    container.invalidate(provider);
    await expectLater(
      container.read(provider.future),
      throwsA(isA<AccessFailure>()),
    );
    expect(await store.readAll('user-1'), isEmpty);
  });

  test('Una settimana assente online elimina la vecchia copia, senza fingere un successo offline', () async {
    final auth = FakeAuthRepository()
      ..profile = person(role: UserRole.employee);
    addTearDown(auth.changes.close);
    final store = LocalPlanningStore();
    await store.save('user-1', personal(), 0);
    final repo = FakePersonalPlanning();
    final container = containerFor(auth, repo, store);
    addTearDown(container.dispose);
    final provider = employeePlanningProvider((
      userId: 'user-1',
      monday: monday,
    ));
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    expect((await container.read(provider.future)).planning, isNull);
    expect(await store.read('user-1', monday), isNull);
    repo.error = ClientException('offline');
    container.invalidate(provider);
    await expectLater(
      container.read(provider.future),
      throwsA(isA<AccessFailure>()),
    );
  });

  test(
    'Una mancata scrittura locale non nasconde i dati ricevuti online',
    () async {
      final auth = FakeAuthRepository()
        ..profile = person(role: UserRole.employee);
      addTearDown(auth.changes.close);
      final store = LocalPlanningStore(
        preferences: () => Future.error(StateError('storage indisponibile')),
      );
      final repo = FakePersonalPlanning()..weeks[monday] = personal();
      final container = containerFor(auth, repo, store);
      addTearDown(container.dispose);
      final provider = employeePlanningProvider((
        userId: 'user-1',
        monday: monday,
      ));
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      final result = await container.read(provider.future);
      expect(result.cacheWriteFailed, isTrue);
      expect(result.planning, isNotNull);
    },
  );

  Future<void> mount(
    WidgetTester tester,
    FakeAuthRepository auth,
    LocalPlanningStore store,
  ) async {
    addTearDown(auth.changes.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          localPlanningStoreProvider.overrideWithValue(store),
        ],
        child: const ShiftUmcApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Riapro con sessione ripristinata e rete assente: consulto la copia, poi il logout la elimina',
    (tester) async {
      final store = LocalPlanningStore();
      await store.save('user-1', personal(), 0);
      final auth = FakeAuthRepository()
        ..id = 'user-1'
        ..profileError = ClientException('offline');
      await mount(tester, auth, LocalPlanningStore());
      expect(find.text('Pianificazione locale'), findsOneWidget);
      expect(find.text('Sportello salvato'), findsOneWidget);
      expect(find.textContaining('Copia locale salvata il'), findsOneWidget);
      expect(find.text('Gestisci settimane'), findsNothing);
      await tester.tap(find.text('Esci'));
      await tester.pumpAndSettle();
      expect(find.text('Accedi al tuo ufficio'), findsOneWidget);
      expect(await LocalPlanningStore().readAll('user-1'), isEmpty);
    },
  );

  testWidgets('Senza sessione non apro copie persistenti', (tester) async {
    final store = LocalPlanningStore();
    await store.save('user-1', personal(), 0);
    await mount(tester, FakeAuthRepository(), store);
    expect(find.text('Accedi al tuo ufficio'), findsOneWidget);
    expect(find.text('Sportello salvato'), findsNothing);
  });

  testWidgets('Offline un altro account non vede la copia del primo', (
    tester,
  ) async {
    final store = LocalPlanningStore();
    await store.save('user-1', personal(), 0);
    final auth = FakeAuthRepository()
      ..id = 'user-2'
      ..profileError = ClientException('offline');
    await mount(tester, auth, store);
    expect(find.text('Sportello salvato'), findsNothing);
    expect(
      find.textContaining('Nessuna pianificazione salvata per questo account.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Un account disattivato dal server non apre la copia e la cancella',
    (tester) async {
      final store = LocalPlanningStore();
      await store.save('user-1', personal(), 0);
      final auth = FakeAuthRepository()
        ..id = 'user-1'
        ..profile = person(role: UserRole.employee, active: false);
      await mount(tester, auth, store);
      expect(find.text('Pianificazione locale'), findsNothing);
      expect(find.text('Sportello salvato'), findsNothing);
      expect(find.textContaining('Account disattivato'), findsOneWidget);
      expect(await store.readAll('user-1'), isEmpty);
    },
  );
}
