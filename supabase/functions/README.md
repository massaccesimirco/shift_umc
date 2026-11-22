# Creazione dipendenti

`create-employee` riceve nome, cognome, email e password iniziale dall’app.
Verifica la sessione con Auth e il ruolo nel database, poi crea l’account.
La migrazione `005` crea il profilo con un trigger: se il profilo non può
essere inserito, anche la creazione dell’account fallisce.

Il ruolo è sempre EMPLOYEE. La funzione usa una chiave amministrativa già
presente nell’ambiente delle Edge Functions, mai nel codice Flutter.
Non invia email: `email_confirm: true` abilita l’accesso senza verifica della
casella. Il cambio password è disponibile nel profilo, ma non è obbligatorio
al primo accesso. La disattivazione blocca i dati tramite RLS, non cancella Auth.

## Attivazione su Supabase

1. Nel SQL Editor eseguire una volta `migrations/202610190005_create_employees.sql`
   dopo le migrazioni precedenti. Non eseguire gli script di test nel database reale.
2. In Edge Functions creare la funzione **create-employee** tramite editor.
   Copiare i due file della cartella `create-employee`: `index.ts` e `handler.ts`,
   mantenendo i nomi. `handler_test.ts` serve soltanto ai test locali.
3. Disabilitare per questa funzione il controllo JWT legacy della piattaforma
   (Verify JWT). La funzione verifica comunque ogni token con Auth e respinge
   richieste anonime, dipendenti e amministratori disattivati.
4. Pubblicare la funzione e riavviare l’app. Non aggiungere la service-role key
   ai file Flutter o alla configurazione locale dell’app.

Alternativa, con Supabase CLI installata e autenticata, dalla radice del progetto:

```sh
supabase functions deploy create-employee --project-ref IL_PROJECT_REF --no-verify-jwt
```

Il file `supabase/config.toml` contiene la stessa impostazione JWT.

## Prova completa

Dall’account amministratore: Gestisci dipendenti → Aggiungi dipendente.
Creare un account di prova, uscire e accedere con le nuove credenziali.
Cambiare password, uscire e accedere con la nuova password.
Rientrare come amministratore e provare disattivazione e riattivazione.
Un’email già usata non va riutilizzata: controllare anche i disattivati.
Se una richiesta termina con errore di rete, aggiornare l’elenco prima di riprovare.

Test del gestore HTTP con Deno (nessun accesso di rete o credenziali):

```sh
deno test supabase/functions/create-employee/handler_test.ts
```
