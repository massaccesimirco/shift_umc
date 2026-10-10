# ShiftUMC

Progetto Flutter per la pianificazione settimanale dei dipendenti di un ufficio.
La settimana comprende lunedì–venerdì, con fasce Mattina e Pomeriggio.
Target: Web, Android e iOS.

## Stato

- Login email/password e profili amministratore/dipendente con Supabase.
- Gestione mansioni: creazione, modifica, disattivazione e riattivazione.
- Gestione dipendenti esistenti: modifica nome/cognome e stato attivo.
- Pianificazione disponibile come demo in memoria.

## Struttura

Flutter e Material 3 per l'interfaccia, Riverpod per lo stato, Supabase Auth e
PostgreSQL per autenticazione e dati. `lib` separa schermate, provider, servizi,
repository e modelli. Le migrazioni e i test SQL sono in `supabase`.

## Avvio

Copiare `config/supabase.example.json` in `config/supabase.local.json` e compilare
URL e chiave pubblica Supabase. 
Il file locale è escluso da Git.

```sh
flutter pub get
flutter run -d chrome --dart-define-from-file=config/supabase.local.json
```


## Verifiche

```sh
flutter analyze
flutter test
```

La disattivazione conserva lo storico; i permessi sono controllati nel database con RLS. Non elimina l'account
Auth né rimuove istantaneamente dati già visualizzati.

Per avviare la demo separata della pianificazione:

```sh
flutter run -d chrome --dart-define=SHIFTUMC_DEMO=true
```
