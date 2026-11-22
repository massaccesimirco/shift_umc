import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_umc/app/app.dart';
import 'package:shift_umc/models/access_failure.dart';
import 'package:shift_umc/models/planning.dart';
import 'package:shift_umc/providers/auth_providers.dart';
import 'package:shift_umc/providers/employee_providers.dart';
import 'package:shift_umc/repositories/employee_repository.dart';
import 'package:shift_umc/services/employee_service.dart';

import 'auth_test.dart' show FakeAuthRepository, person;

UserProfile employee({
  String first = 'Mario',
  String last = 'Rossi',
  bool active = true,
}) => UserProfile(
  id: 'employee-1',
  firstName: first,
  lastName: last,
  email: 'mario@example.invalid',
  role: UserRole.employee,
  active: active,
);

class FakeEmployees implements EmployeeRepository {
  List<UserProfile> rows = [employee()];
  Object? readError, writeError;
  Completer<void>? pending;
  int reads = 0, writes = 0;
  @override
  Future<List<UserProfile>> list() async {
    reads++;
    if (readError != null) throw readError!;
    return rows.toList();
  }

  @override
  Future<void> create(
    String firstName,
    String lastName,
    String email,
    String password,
  ) async {
    writes++;
    if (pending != null) await pending!.future;
    if (writeError != null) throw writeError!;
    rows.add(
      UserProfile(
        id: 'new-employee',
        firstName: firstName,
        lastName: lastName,
        email: email,
        role: UserRole.employee,
      ),
    );
  }

  @override
  Future<void> rename(String id, String firstName, String lastName) async {
    writes++;
    if (pending != null) await pending!.future;
    if (writeError != null) throw writeError!;
    rows = [
      employee(first: firstName, last: lastName, active: rows.single.active),
    ];
  }

  @override
  Future<void> setActive(String id, bool active) async {
    writes++;
    if (writeError != null) throw writeError!;
    rows = [
      employee(
        first: rows.single.firstName,
        last: rows.single.lastName,
        active: active,
      ),
    ];
  }
}

void main() {
  test('Autorizzazione, amministratori protetti e validazione prima del repository', () async {
    final repo = FakeEmployees();
    for (final actor in [
      person(role: UserRole.employee),
      person(active: false),
    ]) {
      final service = EmployeeService(repo, actor);
      await expectLater(service.list(), throwsA(isA<AccessFailure>()));
      await expectLater(
        service.rename(employee(), 'Anna', 'Verdi'),
        throwsA(isA<AccessFailure>()),
      );
      await expectLater(
        service.setActive(employee(), false),
        throwsA(isA<AccessFailure>()),
      );
    }
    final service = EmployeeService(repo, person());
    await expectLater(
      service.rename(person(), 'No', 'Admin'),
      throwsA(isA<AccessFailure>()),
    );
    await expectLater(
      service.setActive(person(), false),
      throwsA(isA<AccessFailure>()),
    );
    for (final value in ['', '   ', 'a' * 121]) {
      await expectLater(
        service.rename(employee(), value, 'Rossi'),
        throwsA(isA<AccessFailure>()),
      );
      await expectLater(
        service.rename(employee(), 'Mario', value),
        throwsA(isA<AccessFailure>()),
      );
    }
    expect(repo.reads, 0);
    expect(repo.writes, 0);
    await service.rename(employee(), ' Anna ', ' Verdi ');
    expect(repo.rows.single.fullName, 'Anna Verdi');
  });
  Future<FakeAuthRepository> mount(
    WidgetTester tester,
    FakeEmployees repo, {
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
          employeeRepositoryProvider.overrideWithValue(repo),
        ],
        child: const ShiftUmcApp(),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Gestisci dipendenti'));
    await tester.pumpAndSettle();
  }

  testWidgets('Dipendente senza pulsante e senza richieste al catalogo', (
    tester,
  ) async {
    final repo = FakeEmployees();
    await mount(tester, repo, role: UserRole.employee);
    expect(find.text('Gestisci dipendenti'), findsNothing);
    expect(repo.reads, 0);
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'Modifica, annulla disattivazione, disattiva e riattiva a $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = FakeEmployees();
        await mount(tester, repo);
        await open(tester);
        expect(find.text('Mario Rossi'), findsOneWidget);
        await tester.tap(find.text('Modifica'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), '');
        await tester.tap(find.text('Salva'));
        await tester.pumpAndSettle();
        expect(repo.writes, 0);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nome'),
          'Anna',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Cognome'),
          'Verdi',
        );
        await tester.tap(find.text('Salva'));
        await tester.pumpAndSettle();
        expect(find.text('Anna Verdi'), findsOneWidget);
        await tester.tap(find.text('Disattiva'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Annulla'));
        await tester.pumpAndSettle();
        expect(repo.rows.single.active, isTrue);
        await tester.tap(find.text('Disattiva'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Disattiva'));
        await tester.pumpAndSettle();
        expect(find.text('Anna Verdi'), findsNothing);
        await tester.tap(find.text('Mostra anche i disattivati'));
        await tester.pumpAndSettle();
        expect(find.text('Disattivato'), findsOneWidget);
        await tester.tap(find.text('Riattiva'));
        await tester.pumpAndSettle();
        expect(repo.rows.single.active, isTrue);
        await tester.tap(find.text('Esci'));
        await tester.pumpAndSettle();
        expect(find.text('Anna Verdi'), findsNothing);
        expect(find.text('Accedi al tuo ufficio'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Lettura fallita, retry e lista vuota', (tester) async {
    final repo = FakeEmployees()..readError = Exception('private-detail');
    await mount(tester, repo);
    await open(tester);
    expect(find.textContaining('Servizio non raggiungibile'), findsOneWidget);
    expect(find.textContaining('private-detail'), findsNothing);
    repo.readError = null;
    repo.rows = [];
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nessun dipendente presente'), findsOneWidget);
  });
  testWidgets(
    'Errore mantiene i nomi inseriti, salva bloccato durante la richiesta',
    (tester) async {
      final repo = FakeEmployees()
        ..pending = Completer<void>()
        ..writeError = const AccessFailure('Modifica non consentita.');
      await mount(tester, repo);
      await open(tester);
      await tester.tap(find.text('Modifica'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome'),
        'Anna',
      );
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
      expect(find.text('Modifica non consentita.'), findsOneWidget);
      expect(find.text('Anna'), findsOneWidget);
      repo.pending = null;
      repo.writeError = null;
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();
      expect(find.text('Anna Rossi'), findsOneWidget);
    },
  );
  testWidgets('Disattivazione fallita conserva il dipendente attivo', (
    tester,
  ) async {
    final repo = FakeEmployees()
      ..writeError = const AccessFailure('Modifica non consentita.');
    await mount(tester, repo);
    await open(tester);
    await tester.tap(find.text('Disattiva'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Disattiva'));
    await tester.pumpAndSettle();
    expect(find.text('Modifica non consentita.'), findsOneWidget);
    expect(repo.rows.single.active, isTrue);
  });
}
