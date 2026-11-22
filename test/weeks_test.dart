import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_umc/app/app.dart';
import 'package:shift_umc/models/access_failure.dart';
import 'package:shift_umc/models/planning.dart';
import 'package:shift_umc/providers/auth_providers.dart';
import 'package:shift_umc/providers/week_providers.dart';
import 'package:shift_umc/repositories/week_repository.dart';
import 'package:shift_umc/services/week_service.dart';

import 'auth_test.dart' show FakeAuthRepository, person;

class FakeWeeks implements WeekRepository {
  final rows = <DateTime, WeekPlan>{};
  int reads = 0, writes = 0;
  Object? readError, writeError;
  Completer<void>? pending;
  @override
  Future<WeekPlan?> find(DateTime monday) async {
    reads++;
    if (readError != null) throw readError!;
    return rows[monday];
  }

  @override
  Future<WeekPlan> createDraft(DateTime monday, String createdBy) async {
    writes++;
    if (pending != null) await pending!.future;
    if (writeError != null) throw writeError!;
    if (rows.containsKey(monday)) {
      throw const AccessFailure(
        'Questa settimana esiste già. Premi Aggiorna per aprirla.',
      );
    }
    return rows[monday] = WeekPlan(
      id: 'week-$writes',
      startDate: monday,
      status: WeekStatus.draft,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );
  }
}

void main() {
  test(
    'Ruolo, stato attivo e lunedì controllati prima di accedere al repository',
    () async {
      final repo = FakeWeeks();
      final monday = DateTime(2026, 10, 5);
      for (final actor in [
        person(role: UserRole.employee),
        person(active: false),
      ]) {
        final service = WeekService(repo, actor);
        await expectLater(service.find(monday), throwsA(isA<AccessFailure>()));
        await expectLater(
          service.createDraft(monday),
          throwsA(isA<AccessFailure>()),
        );
      }
      final service = WeekService(repo, person());
      await expectLater(
        service.createDraft(addDays(monday, 1)),
        throwsA(isA<AccessFailure>()),
      );
      expect(repo.reads, 0);
      expect(repo.writes, 0);
      final plan = await service.createDraft(DateTime(2026, 10, 5, 23));
      expect(plan.startDate, monday);
      expect(plan.createdBy, person().id);
      expect(plan.status, WeekStatus.draft);
    },
  );

  Future<void> mount(
    WidgetTester tester,
    FakeWeeks repo, {
    UserRole role = UserRole.admin,
  }) async {
    final auth = FakeAuthRepository()
      ..id = 'user-1'
      ..profile = person(role: role);
    addTearDown(auth.changes.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          weekRepositoryProvider.overrideWithValue(repo),
        ],
        child: const ShiftUmcApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Gestisci settimane'));
    await tester.tap(find.text('Gestisci settimane'));
    await tester.pumpAndSettle();
  }

  testWidgets('Dipendente senza gestione settimane e senza richieste', (
    tester,
  ) async {
    final repo = FakeWeeks();
    await mount(tester, repo, role: UserRole.employee);
    expect(find.text('Gestisci settimane'), findsNothing);
    expect(repo.reads, 0);
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('Crea, cambia settimana e ritrova la bozza a $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeWeeks();
      await mount(tester, repo);
      await open(tester);
      await tester.tap(find.text('Crea bozza'));
      await tester.pumpAndSettle();
      expect(find.text('Bozza'), findsOneWidget);
      expect(repo.writes, 1);
      await tester.tap(find.byTooltip('Settimana successiva'));
      await tester.pumpAndSettle();
      expect(find.text('Crea bozza'), findsOneWidget);
      await tester.tap(find.byTooltip('Settimana precedente'));
      await tester.pumpAndSettle();
      expect(find.text('Bozza'), findsOneWidget);
      await tester.tap(find.byTooltip('Torna al profilo'));
      await tester.pumpAndSettle();
      await open(tester);
      expect(find.text('Bozza'), findsOneWidget);
      await tester.tap(find.text('Esci'));
      await tester.pumpAndSettle();
      expect(find.text('Bozza'), findsNothing);
      expect(find.text('Accedi al tuo ufficio'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Lettura fallita non offre creazione, retry recupera', (
    tester,
  ) async {
    final repo = FakeWeeks()..readError = Exception('dettaglio interno');
    await mount(tester, repo);
    await open(tester);
    expect(find.text('Crea bozza'), findsNothing);
    expect(find.textContaining('dettaglio interno'), findsNothing);
    expect(find.textContaining('Servizio non raggiungibile'), findsOneWidget);
    repo.readError = null;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Crea bozza'), findsOneWidget);
  });

  testWidgets(
    'Richiesta in corso blocca doppio invio e navigazione; errore recuperabile',
    (tester) async {
      final repo = FakeWeeks()
        ..pending = Completer<void>()
        ..writeError = const AccessFailure('Creazione non consentita.');
      await mount(tester, repo);
      await open(tester);
      await tester.tap(find.text('Crea bozza'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Creazione…'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Settimana successiva',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(repo.writes, 1);
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Creazione non consentita.'), findsOneWidget);
      expect(find.text('Bozza'), findsNothing);
      repo.pending = null;
      repo.writeError = null;
      await tester.tap(find.text('Crea bozza'));
      await tester.pumpAndSettle();
      expect(find.text('Bozza'), findsOneWidget);
    },
  );

  testWidgets(
    'Bozza creata da un altro amministratore: aggiorna dopo conflitto',
    (tester) async {
      final repo = FakeWeeks();
      await mount(tester, repo);
      await open(tester);
      await repo.createDraft(mondayOf(DateTime.now()), 'other-admin');
      await tester.tap(find.text('Crea bozza'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Questa settimana esiste già'),
        findsOneWidget,
      );
      await tester.tap(find.text('Aggiorna'));
      await tester.pumpAndSettle();
      expect(find.text('Bozza'), findsOneWidget);
      expect(repo.rows.length, 1);
    },
  );
}
