-- Applico questa seconda migrazione dopo 202610040001, senza rieseguire la prima.
begin;

alter table public.duty add constraint duty_name_length
  check (char_length(trim(name)) between 1 and 120);

-- Concedo privilegi sulle sole colonne modificabili, senza DELETE o modifica dell’ID.
grant insert (name, type, exclusive, active), update (name, type, exclusive, active)
  on public.duty to authenticated;
create policy duty_admin_insert on public.duty for insert to authenticated
  with check ((select private.is_admin()));
create policy duty_admin_update on public.duty for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

-- Impedisco di cambiare retroattivamente le regole di una mansione già assegnata.
-- Uso SECURITY DEFINER per controllare anche le assegnazioni nascoste al chiamante.
create function private.protect_assigned_duty() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (new.type is distinct from old.type or new.exclusive is distinct from old.exclusive)
     and exists (select 1 from public.assignment where duty_id = old.id) then
    raise exception 'assigned_duty_rules_locked' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function private.protect_assigned_duty() from public, anon, authenticated;
create trigger protect_assigned_duty before update on public.duty
  for each row execute function private.protect_assigned_duty();

commit;
