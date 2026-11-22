import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_umc/app/app.dart';
import 'package:shift_umc/config/backend_config.dart';
import 'package:shift_umc/models/access_failure.dart';
import 'package:shift_umc/models/planning.dart';
import 'package:shift_umc/providers/auth_providers.dart';
import 'package:shift_umc/repositories/auth_repository.dart';
import 'package:shift_umc/services/auth_service.dart';

class FakeAuthRepository implements AuthRepository {
  final changes = StreamController<String?>.broadcast();
  String? id;
  UserProfile? profile;
  Object? loginError;
  Object? profileError;
  Completer<void>? pendingLogin;
  int signInCalls = 0;
  int profileReads = 0;
  String? receivedEmail, receivedPassword;
  @override
  Stream<String?> get userIds async* {
    yield id;
    yield* changes.stream;
  }

  @override
  Future<void> signIn(String email, String password) async {
    signInCalls++;
    receivedEmail = email;
    receivedPassword = password;
    if (pendingLogin != null) await pendingLogin!.future;
    if (loginError != null) throw loginError!;
    id = 'user-1';
    changes.add(id);
  }

  @override
  Future<void> updatePassword(String password) async {
    receivedPassword = password;
  }

  @override
  Future<void> signOut() async {
    id = null;
    changes.add(null);
  }

  @override
  Future<UserProfile?> profileFor(String userId) async {
    profileReads++;
    if (profileError != null) throw profileError!;
    return profile;
  }
}

UserProfile person({
  UserRole role = UserRole.admin,
  bool active = true,
  String id = 'user-1',
}) => UserProfile(
  id: id,
  firstName: 'Mirco',
  lastName: 'Test',
  email: 'mirco@example.invalid',
  role: role,
  active: active,
);

void main() {
  test('Configurazione: soltanto HTTPS e chiavi pubbliche', () {
    expect(const BackendConfig(url: '', publicKey: '').isValid, isFalse);
    expect(
      const BackendConfig(
        url: 'http://example.com',
        publicKey: 'sb_publishable_demo',
      ).isValid,
      isFalse,
    );
    expect(
      const BackendConfig(
        url: 'https://example.com',
        publicKey: 'sb_secret_demo',
      ).isValid,
      isFalse,
    );
    expect(
      const BackendConfig(
        url: 'https://example.com',
        publicKey: 'sb_publishable_demo',
      ).isValid,
      isTrue,
    );
    String key(String role) =>
        'header.${base64Url.encode(utf8.encode(jsonEncode({'role': role})))}.signature';
    expect(
      BackendConfig(url: 'https://example.com', publicKey: key('anon')).isValid,
      isTrue,
    );
    expect(
      BackendConfig(
        url: 'https://example.com',
        publicKey: key('service_role'),
      ).isValid,
      isFalse,
    );
  });
  test(
    'Profilo mancante, disattivo o di altro account: accesso negato',
    () async {
      final repo = FakeAuthRepository();
      addTearDown(repo.changes.close);
      final service = AuthService(repo);
      for (final profile in [
        null,
        person(active: false),
        person(id: 'other'),
      ]) {
        repo.profile = profile;
        await expectLater(
          service.requireProfile('user-1'),
          throwsA(isA<AccessFailure>()),
        );
      }
    },
  );
  test(
    'Pulisce gli spazi nella email, conserva esattamente la password',
    () async {
      final repo = FakeAuthRepository();
      addTearDown(repo.changes.close);
      await AuthService(repo).signIn(' mirco@example.invalid ', ' password ');
      expect(repo.receivedEmail, 'mirco@example.invalid');
      expect(repo.receivedPassword, ' password ');
    },
  );

  Future<void> mount(WidgetTester tester, FakeAuthRepository repo) async {
    addTearDown(repo.changes.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: const ShiftUmcApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterLogin(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'mirco@example.invalid',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'test-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Accedi'));
    await tester.pumpAndSettle();
  }

  for (final role in UserRole.values) {
    testWidgets('Login e logout ${role.name} su telefono', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeAuthRepository()..profile = person(role: role);
      await mount(tester, repo);
      await enterLogin(tester);
      expect(find.text('Benvenuto, Mirco Test'), findsOneWidget);
      expect(
        find.text(role == UserRole.admin ? 'Amministratore' : 'Dipendente'),
        findsOneWidget,
      );
      expect(find.textContaining('Mario'), findsNothing);
      await tester.tap(find.text('Esci'));
      await tester.pumpAndSettle();
      expect(find.text('Accedi al tuo ufficio'), findsOneWidget);
      expect(find.text('Benvenuto, Mirco Test'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Campi vuoti non inviano richieste', (tester) async {
    final repo = FakeAuthRepository();
    await mount(tester, repo);
    await tester.tap(find.text('Accedi'));
    await tester.pumpAndSettle();
    expect(repo.signInCalls, 0);
    expect(find.text('Inserisci la password.'), findsOneWidget);
  });
  testWidgets('Errore credenziali comprensibile e nuovo tentativo', (
    tester,
  ) async {
    final repo = FakeAuthRepository()
      ..loginError = const AccessFailure('Email o password non corrette.');
    await mount(tester, repo);
    await enterLogin(tester);
    expect(find.text('Email o password non corrette.'), findsOneWidget);
    repo.loginError = null;
    repo.profile = person();
    await tester.tap(find.text('Accedi'));
    await tester.pumpAndSettle();
    expect(find.text('Amministratore'), findsOneWidget);
  });
  testWidgets('Il pulsante blocca richieste duplicate', (tester) async {
    final repo = FakeAuthRepository()
      ..pendingLogin = Completer<void>()
      ..profile = person();
    await mount(tester, repo);
    await enterLogin(tester);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(repo.signInCalls, 1);
    repo.pendingLogin!.complete();
    await tester.pumpAndSettle();
  });
  testWidgets('Sessione ripristinata e disattivazione alla rilettura', (
    tester,
  ) async {
    final repo = FakeAuthRepository()
      ..id = 'user-1'
      ..profile = person();
    await mount(tester, repo);
    expect(find.text('Amministratore'), findsOneWidget);
    repo.profile = null;
    await tester.tap(find.text('Aggiorna profilo'));
    await tester.pumpAndSettle();
    expect(find.text('Amministratore'), findsNothing);
    expect(
      find.textContaining('Account disattivato o non abilitato'),
      findsOneWidget,
    );
    await tester.tap(find.text('Esci'));
    await tester.pumpAndSettle();
    expect(find.text('Accedi al tuo ufficio'), findsOneWidget);
  });
  testWidgets(
    'Account non abilitato: messaggio subito, nessun retry automatico e ritorno al login',
    (tester) async {
      final repo = FakeAuthRepository();
      await mount(tester, repo);
      await enterLogin(tester);
      expect(
        find.textContaining('Account disattivato o non abilitato'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(repo.profileReads, 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(repo.profileReads, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('Torna al login'));
      await tester.pumpAndSettle();
      expect(find.text('Accedi al tuo ufficio'), findsOneWidget);
    },
  );
  testWidgets('Account riattivato: Riprova rilegge il profilo', (tester) async {
    final repo = FakeAuthRepository()
      ..id = 'user-1'
      ..profile = person(active: false);
    await mount(tester, repo);
    expect(find.textContaining('Account disattivato'), findsOneWidget);
    repo.profile = person();
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Benvenuto, Mirco Test'), findsOneWidget);
  });
  testWidgets('Errore rete sul profilo: retry senza dati demo', (tester) async {
    final repo = FakeAuthRepository()
      ..id = 'user-1'
      ..profileError = Exception('private-details');
    await mount(tester, repo);
    expect(find.textContaining('Servizio non raggiungibile'), findsOneWidget);
    expect(find.textContaining('private-details'), findsNothing);
    repo.profileError = null;
    repo.profile = person();
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Amministratore'), findsOneWidget);
  });
}
