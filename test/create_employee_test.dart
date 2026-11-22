import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_umc/app/app.dart';
import 'package:shift_umc/models/access_failure.dart';
import 'package:shift_umc/models/password_rules.dart';
import 'package:shift_umc/models/planning.dart';
import 'package:shift_umc/providers/auth_providers.dart';
import 'package:shift_umc/providers/employee_providers.dart';
import 'package:shift_umc/services/employee_service.dart';
import 'package:shift_umc/services/auth_service.dart';

import 'auth_test.dart' show FakeAuthRepository, person;
import 'employees_test.dart' show FakeEmployees;

void main() {
  test('Password: lunghezza minima e limite UTF-8 del servizio Auth', () {
    expect(passwordError('short'), isNotNull);
    expect(passwordError('x' * 72), isNull);
    expect(passwordError('x' * 73), isNotNull);
    expect(passwordError('😀' * 19), isNotNull);
  });
  test('Creazione riservata ad admin attivo e dati validati', () async {
    final repo = FakeEmployees();
    for (final actor in [
      person(role: UserRole.employee),
      person(active: false),
    ]) {
      await expectLater(
        EmployeeService(
          repo,
          actor,
        ).create('Anna', 'Verdi', 'anna@example.invalid', 'password-test'),
        throwsA(isA<AccessFailure>()),
      );
    }
    final service = EmployeeService(repo, person());
    for (final values in [
      ['', 'Verdi', 'anna@example.invalid', 'password-test'],
      ['Anna', 'a' * 121, 'anna@example.invalid', 'password-test'],
      ['Anna', 'Verdi', 'email-errata', 'password-test'],
      ['Anna', 'Verdi', 'anna@example.invalid', 'corta'],
    ]) {
      await expectLater(
        service.create(values[0], values[1], values[2], values[3]),
        throwsA(isA<AccessFailure>()),
      );
    }
    expect(repo.writes, 0);
    await service.create(
      ' Anna ',
      ' Verdi ',
      ' ANNA@example.invalid ',
      'password-test',
    );
    expect(repo.rows.last.fullName, 'Anna Verdi');
    expect(repo.rows.last.email, 'anna@example.invalid');
  });

  Future<FakeAuthRepository> mount(
    WidgetTester tester,
    FakeEmployees repo,
  ) async {
    final auth = FakeAuthRepository()
      ..id = 'user-1'
      ..profile = person();
    addTearDown(auth.changes.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          employeeRepositoryProvider.overrideWithValue(repo),
        ],
        child: const ShiftUmcApp(),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  Future<void> openCreate(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Gestisci dipendenti'));
    await tester.tap(find.text('Gestisci dipendenti'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiungi dipendente'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'Anna');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Cognome'),
      'Verdi',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'anna@example.invalid',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password iniziale'),
      'password-test',
    );
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'Creazione e rilettura elenco a $width senza cambiare sessione',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = FakeEmployees()..rows = [];
        final auth = await mount(tester, repo);
        await openCreate(tester);
        await tester.tap(find.text('Crea dipendente'));
        await tester.pumpAndSettle();
        expect(repo.writes, 0);
        await fill(tester);
        await tester.tap(find.text('Crea dipendente'));
        await tester.pumpAndSettle();
        expect(find.text('Anna Verdi'), findsOneWidget);
        expect(auth.id, 'user-1');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Errore conserva il modulo e invio pendente non duplicabile', (
    tester,
  ) async {
    final repo = FakeEmployees()
      ..pending = Completer<void>()
      ..writeError = const AccessFailure(
        'Esiste già un account con questa email.',
      );
    await mount(tester, repo);
    await openCreate(tester);
    await fill(tester);
    await tester.tap(find.text('Crea dipendente'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Crea dipendente'),
          )
          .onPressed,
      isNull,
    );
    expect(repo.writes, 1);
    repo.pending!.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('Esiste già un account con questa email.'),
      findsOneWidget,
    );
    expect(find.text('Anna'), findsOneWidget);
    expect(repo.rows.length, 1);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(find.text('Password iniziale'), findsNothing);
  });
  testWidgets('Cambio password: conferma necessaria e successo', (
    tester,
  ) async {
    final auth = await mount(tester, FakeEmployees());
    await tester.tap(find.text('Cambia password'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nuova password'),
      'nuova-password',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Conferma password'),
      'diversa',
    );
    await tester.tap(find.text('Salva password'));
    await tester.pumpAndSettle();
    expect(auth.receivedPassword, isNull);
    expect(find.text('Le password non coincidono.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Conferma password'),
      'nuova-password',
    );
    await tester.tap(find.text('Salva password'));
    await tester.pumpAndSettle();
    expect(auth.receivedPassword, 'nuova-password');
    expect(find.text('Password aggiornata.'), findsOneWidget);
  });
  test('Cambio password non consentito al profilo disattivato', () async {
    final auth = FakeAuthRepository()..profile = person(active: false);
    addTearDown(auth.changes.close);
    await expectLater(
      AuthService(auth).updatePassword('user-1', 'nuova-password'),
      throwsA(isA<AccessFailure>()),
    );
    expect(auth.receivedPassword, isNull);
  });
}
