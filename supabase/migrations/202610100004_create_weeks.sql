-- Consento agli amministratori di creare settimane in bozza.
begin;

grant insert (start_date, created_by) on public.week_plan to authenticated;
create policy week_admin_insert on public.week_plan
  for insert to authenticated
  with check (
    (select private.is_admin())
    and created_by = (select auth.uid())
    and status = 'DRAFT'
    and published_at is null
  );

-- Affido stato, identificativo e data di registrazione ai default del database.
-- Mantengo bloccati UPDATE e DELETE; implementerò la pubblicazione separatamente.
commit;
