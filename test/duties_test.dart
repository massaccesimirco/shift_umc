import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_umc/app/app.dart';
import 'package:shift_umc/models/access_failure.dart';
import 'package:shift_umc/models/planning.dart';
import 'package:shift_umc/providers/auth_providers.dart';
import 'package:shift_umc/providers/duty_providers.dart';
import 'package:shift_umc/repositories/duty_repository.dart';
import 'package:shift_umc/services/duty_service.dart';

import 'auth_test.dart' show FakeAuthRepository, person;

class FakeDuties implements DutyRepository {
  final rows = <Duty>[];
  Object? error;
  Completer<void>? pending;
  int writes = 0;
  @override
  Future<List<Duty>> list() async => rows.toList();
  @override
  Future<void> save({
    String? id,
    required String name,
    required DutyType type,
    required bool exclusive,
  }) async {
    writes++;
    if (pending != null) await pending!.future;
    if (error != null) throw error!;
    final index = rows.indexWhere((d) => d.id == id);
    final duty = Duty(
      id: id ?? 'd${rows.length}',
      name: name,
      type: type,
      exclusive: exclusive,
      active: index < 0 ? true : rows[index].active,
    );
    if (index < 0) {
      rows.add(duty);
    } else {
      rows[index] = duty;
    }
  }

  @override
  Future<void> setActive(String id, bool active) async {
    final i = rows.indexWhere((d) => d.id == id);
    final d = rows[i];
    rows[i] = Duty(
      id: id,
      name: d.name,
      type: d.type,
      exclusive: d.exclusive,
      active: active,
    );
  }
}

void main() {
  test(
    'Solo admin attivi, nomi validi e stati esclusivi arrivano al repository',
    () async {
      final repo = FakeDuties();
      for (final profile in [
        person(role: UserRole.employee),
        person(active: false),
      ]) {
        final service = DutyService(repo, profile);
        await expectLater(
          service.save(
            name: 'Sportello',
            type: DutyType.activity,
            exclusive: false,
          ),
          throwsA(isA<AccessFailure>()),
        );
        await expectLater(
          service.setActive('d0', false),
          throwsA(isA<AccessFailure>()),
        );
      }
      final service = DutyService(repo, person());
      for (final name in ['', '   ', 'a' * 121]) {
        await expectLater(
          service.save(name: name, type: DutyType.activity, exclusive: false),
          throwsA(isA<AccessFailure>()),
        );
      }
      await expectLater(
        service.save(
          name: 'Sportello',
          type: DutyType.activity,
          exclusive: true,
        ),
        throwsA(isA<AccessFailure>()),
      );
      expect(repo.writes, 0);
      await service.save(
        name: ' Ferie ',
        type: DutyType.status,
        exclusive: true,
      );
      expect(repo.rows.single.name, 'Ferie');
    },
  );

  Future<void> mount(
    WidgetTester tester,
    FakeDuties duties, {
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
          dutyRepositoryProvider.overrideWithValue(duties),
        ],
        child: const ShiftUmcApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Il dipendente non vede la gestione', (tester) async {
    await mount(tester, FakeDuties(), role: UserRole.employee);
    expect(find.text('Gestisci mansioni'), findsNothing);
  });
  testWidgets('Admin su mobile: crea, modifica, disattiva e riattiva', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeDuties();
    await mount(tester, repo);
    await tester.tap(find.text('Gestisci mansioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuova mansione'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(repo.writes, 0);
    await tester.enterText(find.byType(TextFormField), 'Sportello');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Sportello'), findsOneWidget);
    await tester.tap(find.text('Modifica'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Revisioni');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Revisioni'), findsOneWidget);
    await tester.tap(find.text('Disattiva'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Disattiva'));
    await tester.pumpAndSettle();
    expect(find.text('Revisioni'), findsNothing);
    await tester.tap(find.text('Mostra anche le disattivate'));
    await tester.pumpAndSettle();
    expect(find.text('Disattivata'), findsOneWidget);
    await tester.tap(find.text('Riattiva'));
    await tester.pumpAndSettle();
    expect(repo.rows.single.active, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Errore salvataggio conserva il modulo; blocca invii duplicati', (
    tester,
  ) async {
    final repo = FakeDuties()
      ..pending = Completer<void>()
      ..error = const AccessFailure('Nome già presente.');
    await mount(tester, repo);
    await tester.tap(find.text('Gestisci mansioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuova mansione'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Sportello');
    await tester.tap(find.text('Salva'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Salva'))
          .onPressed,
      isNull,
    );
    expect(repo.writes, 1);
    repo.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Nome già presente.'), findsOneWidget);
    expect(find.text('Sportello'), findsOneWidget);
    repo.pending = null;
    repo.error = null;
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.rows.single.name, 'Sportello');
  });
}
