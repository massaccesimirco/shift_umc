-- Terza migrazione: gestione dei profili dipendente già collegati a Supabase Auth.
begin;

alter table public.user_profile add constraint profile_name_length
  check (char_length(trim(first_name)) between 1 and 120
     and char_length(trim(last_name)) between 1 and 120);

-- Si possono modificare solo i dati anagrafici e lo stato attivo.
-- Ruolo, email e identificativo rimangono protetti dai privilegi sulle colonne.
grant update (first_name, last_name, active) on public.user_profile to authenticated;
create policy employee_admin_update on public.user_profile
  for update to authenticated
  using ((select private.is_admin()) and role = 'EMPLOYEE')
  with check ((select private.is_admin()) and role = 'EMPLOYEE');

-- Nessun INSERT/DELETE: creazione account e gestione amministratori restano separate.
-- Le policy di lettura esistenti verificano active a ogni nuova richiesta dati.
commit;
