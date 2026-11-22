-- Creo il profilo dipendente nella stessa transazione dell’account Auth.
begin;

create function private.create_employee_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  employee jsonb := new.raw_app_meta_data -> 'shiftumc_employee';
  actor uuid;
begin
  if employee is null then return new; end if;
  -- Gestisco anche l’aggiunta dei metadata dopo INSERT nella stessa transazione Auth.
  -- Evito che gli aggiornamenti successivi dell’account ricreino il profilo.
  if tg_op = 'UPDATE' and old.raw_app_meta_data -> 'shiftumc_employee' is not null then
    return new;
  end if;
  actor := (employee ->> 'created_by')::uuid;
  -- Ricontrollo il ruolo alla scrittura e mantengo il blocco sulla riga fino al commit.
  perform 1 from public.user_profile
    where id = actor and role = 'ADMIN' and active for share;
  if not found then
    raise exception 'Amministratore non attivo' using errcode = '42501';
  end if;
  insert into public.user_profile(id, first_name, last_name, email, role, active)
  values (new.id, trim(employee ->> 'first_name'), trim(employee ->> 'last_name'),
          lower(new.email), 'EMPLOYEE', true);
  return new;
end;
$$;
revoke all on function private.create_employee_profile() from public, anon, authenticated;

create trigger create_employee_profile
  after insert or update of raw_app_meta_data on auth.users
  for each row execute function private.create_employee_profile();

-- Non concedo INSERT ai client e non uso raw_user_meta_data per creare il profilo.
commit;
