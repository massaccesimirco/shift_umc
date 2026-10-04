import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'config/backend_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const demo = bool.fromEnvironment('SHIFTUMC_DEMO');
  const config = BackendConfig.fromEnvironment();
  String? setupMessage;
  if (!demo) {
    if (!config.isValid) {
      setupMessage = 'Collegamento al servizio non configurato. Completa la configurazione di ShiftUMC prima di accedere.';
    } else {
      try {
        await Supabase.initialize(
          url: config.url,
          publishableKey: config.publicKey,
        );
      } catch (_) {
        setupMessage = 'Impossibile avviare il collegamento. Riavvia l’app e verifica la connessione.';
      }
    }
  }
  runApp(
    ProviderScope(
      child: ShiftUmcApp(demoMode: demo, setupMessage: setupMessage),
    ),
  );
}
