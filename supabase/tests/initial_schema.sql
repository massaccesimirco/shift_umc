-- Eseguire soltanto su un database di test con la migrazione applicata.
-- Tutte le fixture e le modifiche vengono annullate alla fine.
begin;
set local plpgsql.check_asserts = on;

create function pg_temp.expect_error(statement text, expected_code text)
returns void language plpgsql as $$
declare actual_code text;
begin
  begin
    execute statement;
  exception when others then
    get stacked diagnostics actual_code = returned_sqlstate;
    if actual_code = any(string_to_array(expected_code, ',')) then return; end if;
    raise exception 'Atteso SQLSTATE %, ricevuto %: %', expected_code, actual_code, sqlerrm;
  end;
  raise exception 'Operazione accettata erroneamente: %', statement;
end;
$$;

insert into auth.users(id, email) values
 ('10000000-0000-0000-0000-000000000001', 'admin@shift-test.invalid'),
 ('10000000-0000-0000-0000-000000000002', 'mario@shift-test.invalid'),
 ('10000000-0000-0000-0000-000000000003', 'anna@shift-test.invalid'),
 ('10000000-0000-0000-0000-000000000004', 'unprovisioned@shift-test.invalid');
insert into public.user_profile(id, first_name, last_name, email, role) values
 ('10000000-0000-0000-0000-000000000001', 'Admin', 'Test', 'admin@shift-test.invalid', 'ADMIN'),
 ('10000000-0000-0000-0000-000000000002', 'Mario', 'Test', 'mario@shift-test.invalid', 'EMPLOYEE'),
 ('10000000-0000-0000-0000-000000000003', 'Anna', 'Test', 'anna@shift-test.invalid', 'EMPLOYEE');
insert into public.duty(id, name, type) values
 ('20000000-0000-0000-0000-000000000001', 'Mansione test A', 'ACTIVITY'),
 ('20000000-0000-0000-0000-000000000002', 'Mansione test B', 'ACTIVITY');
insert into public.week_plan(id, start_date, status, created_by, published_at) values
 ('30000000-0000-0000-0000-000000000001', '2026-09-21', 'PUBLISHED', '10000000-0000-0000-0000-000000000001', now()),
 ('30000000-0000-0000-0000-000000000002', '2026-09-28', 'DRAFT', '10000000-0000-0000-0000-000000000001', null);
insert into public.assignment(week_plan_id, employee_id, date, period, duty_id) values
 ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', '2026-09-21', 'MORNING', '20000000-0000-0000-0000-000000000001'),
 ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', '2026-09-21', 'MORNING', '20000000-0000-0000-0000-000000000002'),
 ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', '2026-09-21', 'MORNING', '20000000-0000-0000-0000-000000000001'),
 ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '2026-09-28', 'MORNING', '20000000-0000-0000-0000-000000000001');

-- Vincoli eseguiti come proprietario: indipendenti dalle RLS.
select pg_temp.expect_error($s$insert into public.duty(name, type, exclusive) values ('Attività esclusiva', 'ACTIVITY', true)$s$, '23514');
select pg_temp.expect_error($s$insert into public.duty(name, type) values ('Mansione test A', 'ACTIVITY')$s$, '23505');
select pg_temp.expect_error($s$update public.week_plan set start_date = '2026-09-22' where start_date = '2026-09-21'$s$, '23514');
select pg_temp.expect_error($s$update public.week_plan set published_at = null where status = 'PUBLISHED'$s$, '23514');
select pg_temp.expect_error($s$update public.assignment set date = '2026-09-26'$s$, '23514');
select pg_temp.expect_error($s$insert into public.assignment(week_plan_id, employee_id, date, period, duty_id) values ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', '2026-09-21', 'MORNING', '20000000-0000-0000-0000-000000000001')$s$, '23505');
select pg_temp.expect_error($s$update public.assignment set duty_id = '99999999-0000-0000-0000-000000000000' where employee_id = '10000000-0000-0000-0000-000000000003'$s$, '23503');
select pg_temp.expect_error($s$delete from auth.users where id = '10000000-0000-0000-0000-000000000002'$s$, '23503,23001');
select pg_temp.expect_error($s$delete from public.user_profile where id = '10000000-0000-0000-0000-000000000002'$s$, '23503,23001');

-- Anonymous: nessuna lettura né scrittura.
set local role anon;
select pg_temp.expect_error('select * from public.user_profile', '42501');
select pg_temp.expect_error('select * from public.duty', '42501');
select pg_temp.expect_error('select * from public.week_plan', '42501');
select pg_temp.expect_error('select * from public.assignment', '42501');
select pg_temp.expect_error('delete from public.assignment', '42501');
reset role;

-- Un account Auth senza profilo non riceve accesso per il solo fatto di esistere.
set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000004';
do $$ begin
  assert (select count(*) from public.user_profile) = 0;
  assert (select count(*) from public.duty) = 0;
  assert (select count(*) from public.week_plan) = 0;
  assert (select count(*) from public.assignment) = 0;
end $$;

-- Mario legge le proprie due mansioni pubblicate, non la bozza o Anna.
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000002';
do $$ begin
  assert (select count(*) from public.user_profile) = 1;
  assert (select count(*) from public.week_plan) = 1;
  assert (select count(*) from public.assignment) = 2;
  assert not exists (select 1 from public.assignment where employee_id <> auth.uid());
end $$;
select pg_temp.expect_error($s$update public.user_profile set role = 'ADMIN' where id = auth.uid()$s$, '42501');
select pg_temp.expect_error($s$insert into public.duty(name, type) values ('Abuso', 'ACTIVITY')$s$, '42501');
select pg_temp.expect_error($s$update public.week_plan set status = 'PUBLISHED', published_at = now()$s$, '42501');
select pg_temp.expect_error('delete from public.assignment', '42501');
reset role;

-- Disattivazione: niente dati, pur mantenendo lo storico.
update public.user_profile set active = false where id = '10000000-0000-0000-0000-000000000002';
set local role authenticated;
do $$ begin
  assert (select count(*) from public.user_profile) = 0;
  assert (select count(*) from public.duty) = 0;
  assert (select count(*) from public.week_plan) = 0;
  assert (select count(*) from public.assignment) = 0;
end $$;
reset role;

-- Admin: visibilità completa, comprese bozze e dipendenti disattivati.
set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000001';
do $$ begin
  assert (select count(*) from public.user_profile) = 3;
  assert (select count(*) from public.week_plan) = 2;
  assert (select count(*) from public.assignment) = 4;
end $$;
-- La scrittura delle settimane resta una fase successiva anche dopo la gestione mansioni.
select pg_temp.expect_error($s$update public.week_plan set status = 'PUBLISHED', published_at = now()$s$, '42501');
select pg_temp.expect_error('delete from public.user_profile', '42501');
reset role;
update public.user_profile set active = false where id = '10000000-0000-0000-0000-000000000001';
set local role authenticated;
do $$ begin
  assert not private.is_admin();
  assert (select count(*) from public.assignment) = 0;
end $$;
reset role;
rollback;
select 'PASS: vincoli, isolamento dei dipendenti, bozze, disattivazione e scritture negate' as result;
