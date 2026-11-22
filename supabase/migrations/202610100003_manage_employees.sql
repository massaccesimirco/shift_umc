-- Gestisco con la terza migrazione i profili dipendente già collegati a Supabase Auth.
begin;

alter table public.user_profile add constraint profile_name_length
  check (char_length(trim(first_name)) between 1 and 120
     and char_length(trim(last_name)) between 1 and 120);

-- Consento di modificare soltanto i dati anagrafici e lo stato attivo.
-- Proteggo ruolo, email e identificativo tramite i privilegi sulle colonne.
grant update (first_name, last_name, active) on public.user_profile to authenticated;
create policy employee_admin_update on public.user_profile
  for update to authenticated
  using ((select private.is_admin()) and role = 'EMPLOYEE')
  with check ((select private.is_admin()) and role = 'EMPLOYEE');

-- Non concedo INSERT o DELETE: tengo separate creazione account e gestione amministratori.
-- Ricontrollo active a ogni nuova richiesta dati tramite le policy di lettura.
commit;
