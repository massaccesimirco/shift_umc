# ShiftUMC

Progetto Flutter per la pianificazione settimanale dei dipendenti di un ufficio.
La settimana comprende lunedì–venerdì, con fasce Mattina e Pomeriggio.
Target: Web, Android e iOS.

## Stato

- Login email/password e profili amministratore/dipendente con Supabase.
- Gestione mansioni: creazione, modifica, disattivazione e riattivazione.
- Gestione dipendenti: creazione con password iniziale, modifica nome/cognome e stato attivo.
- Cambio password dal profilo personale.
- Settimane: navigazione e creazione di bozze su Supabase (migrazione 004).
- Assegnazioni nelle bozze, pubblicazione e consultazione personale dei turni su Supabase (migrazioni 006 e 007).

## Struttura

Flutter e Material 3 per l'interfaccia, Riverpod per lo stato, Supabase Auth e
PostgreSQL per autenticazione e dati. `lib` separa schermate, provider, servizi,
repository e modelli. Le migrazioni e i test SQL sono in `supabase`.

La creazione dei dipendenti richiede la migrazione `005` e la funzione
`create-employee` pubblicata su Supabase. I passaggi sono in
[supabase/functions/README.md](supabase/functions/README.md).

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
