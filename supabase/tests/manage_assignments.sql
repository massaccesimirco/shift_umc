-- Eseguo questi casi soltanto su un database di test con le migrazioni 001–006.
-- Annullo tutte le fixture alla fine; non uso questo script sul database reale.
begin;
set local plpgsql.check_asserts = on;
create function pg_temp.expect_error(statement text, expected_code text, expected_message text default null)
returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then
    if sqlstate = expected_code and (expected_message is null or sqlerrm = expected_message) then return; end if;
    raise;
  end;
  raise exception 'Operazione accettata erroneamente: %', statement;
end;
$$;

insert into auth.users(id,email) values
 ('60000000-0000-0000-0000-000000000001','admin@assignment-test.invalid'),
 ('60000000-0000-0000-0000-000000000002','employee@assignment-test.invalid'),
 ('60000000-0000-0000-0000-000000000003','inactive@assignment-test.invalid'),
 ('60000000-0000-0000-0000-000000000004','missing@assignment-test.invalid'),
 ('60000000-0000-0000-0000-000000000005','other@assignment-test.invalid');
insert into public.user_profile(id,first_name,last_name,email,role,active) values
 ('60000000-0000-0000-0000-000000000001','Admin','Uno','admin@assignment-test.invalid','ADMIN',true),
 ('60000000-0000-0000-0000-000000000002','Anna','Verdi','employee@assignment-test.invalid','EMPLOYEE',true),
 ('60000000-0000-0000-0000-000000000003','Ex','Dipendente','inactive@assignment-test.invalid','EMPLOYEE',false),
 ('60000000-0000-0000-0000-000000000005','Altro','Dipendente','other@assignment-test.invalid','EMPLOYEE',true);
insert into public.week_plan(id,start_date,created_by,status,published_at) values
 ('61000000-0000-0000-0000-000000000001','2026-11-23','60000000-0000-0000-0000-000000000001','DRAFT',null),
 ('61000000-0000-0000-0000-000000000002','2026-11-30','60000000-0000-0000-0000-000000000001','PUBLISHED',now());
insert into public.duty(id,name,type,exclusive,active) values
 ('62000000-0000-0000-0000-000000000001','Sportello test assegnazioni','ACTIVITY',false,true),
 ('62000000-0000-0000-0000-000000000002','Back office test assegnazioni','ACTIVITY',false,true),
 ('62000000-0000-0000-0000-000000000003','Ferie test assegnazioni','STATUS',true,true),
 ('62000000-0000-0000-0000-000000000004','Disattivata test assegnazioni','ACTIVITY',false,false);

-- Accorcio le chiamate di test senza cambiare l'identità usata dalla funzione pubblica.
create function pg_temp.save(
  ids uuid[], expected jsonb default '[]', day date default '2026-11-23',
  employee uuid default '60000000-0000-0000-0000-000000000002',
  week uuid default '61000000-0000-0000-0000-000000000001',
  notes text default 'note', period public.day_period default 'MORNING'
) returns void language sql as $$
  select public.save_assignment_slot(week,employee,day,period,ids,notes,expected);
$$;

set local role authenticated;
set local "request.jwt.claim.sub" = '60000000-0000-0000-0000-000000000001';
select pg_temp.save(array['62000000-0000-0000-0000-000000000001','62000000-0000-0000-0000-000000000002']::uuid[]);
do $$ begin
 assert (select count(*)=2 from public.assignment where week_plan_id='61000000-0000-0000-0000-000000000001');
end $$;

-- Simulo una fotografia superata: deve fallire senza cancellare il lavoro già salvato.
select pg_temp.expect_error($s$select pg_temp.save('{}'::uuid[])$s$,'P0001','assignment_conflict');
-- Verifico la fascia successiva, ancora vuota, per i dati non validi.
select pg_temp.expect_error($s$select pg_temp.save(array['62000000-0000-0000-0000-000000000003','62000000-0000-0000-0000-000000000001']::uuid[],day=>'2026-11-24')$s$,'P0001','assignment_exclusive_conflict');
select pg_temp.expect_error($s$select pg_temp.save(array['62000000-0000-0000-0000-000000000004']::uuid[],day=>'2026-11-24')$s$,'P0001','assignment_duty_unavailable');
select pg_temp.expect_error($s$select pg_temp.save(array['62000000-0000-0000-0000-000000000099']::uuid[],day=>'2026-11-24')$s$,'P0001','assignment_duty_unavailable');
select pg_temp.expect_error($s$select pg_temp.save(array['62000000-0000-0000-0000-000000000001','62000000-0000-0000-0000-000000000001']::uuid[],day=>'2026-11-24')$s$,'22023','assignment_invalid_input');
select pg_temp.expect_error($s$select pg_temp.save(array[null]::uuid[],day=>'2026-11-24')$s$,'22023','assignment_invalid_input');
select pg_temp.expect_error($s$select pg_temp.save(null,day=>'2026-11-24')$s$,'22023','assignment_invalid_input');
select pg_temp.expect_error($s$select pg_temp.save('{}'::uuid[],notes=>repeat('x',2001),day=>'2026-11-24')$s$,'22023','assignment_invalid_input');
select pg_temp.expect_error($s$select pg_temp.save('{}'::uuid[],expected=>'{}',day=>'2026-11-24')$s$,'22023','assignment_invalid_input');
select pg_temp.expect_error($s$select pg_temp.save('{}'::uuid[],day=>'2026-11-22')$s$,'22023','assignment_invalid_date');
select pg_temp.expect_error($s$select pg_temp.save('{}'::uuid[],day=>'2026-11-28')$s$,'22023','assignment_invalid_date');
select pg_temp.expect_error($s$select pg_temp.save('{}'::uuid[],day=>'2026-11-30')$s$,'22023','assignment_invalid_date');
select pg_temp.expect_error($s$select pg_temp.save('{}'::uuid[],period=>null)$s$,'22023','assignment_invalid_date');
select pg_temp.expect_error($s$select pg_temp.save('{}'::uuid[],employee=>'60000000-0000-0000-0000-000000000001')$s$,'P0001','assignment_employee_unavailable');
select pg_temp.expect_error($s$select pg_temp.save(array['62000000-0000-0000-0000-000000000001']::uuid[],employee=>'60000000-0000-0000-0000-000000000003')$s$,'P0001','assignment_employee_unavailable');
select pg_temp.expect_error($s$select pg_temp.save('{}'::uuid[],employee=>'60000000-0000-0000-0000-000000000004')$s$,'P0001','assignment_employee_unavailable');
select pg_temp.expect_error($s$select pg_temp.save('{}'::uuid[],week=>'61000000-0000-0000-0000-000000000002')$s$,'P0001','assignment_week_not_draft');
select pg_temp.expect_error($s$select pg_temp.save('{}'::uuid[],week=>'61000000-0000-0000-0000-000000000099')$s$,'P0001','assignment_week_not_draft');

-- Verifico una sostituzione rifiutata dopo il confronto della fotografia: le due righe restano.
select pg_temp.expect_error($s$select pg_temp.save(array['62000000-0000-0000-0000-000000000003','62000000-0000-0000-0000-000000000001']::uuid[],
 '[{"duty_id":"62000000-0000-0000-0000-000000000001","notes":"note"},{"duty_id":"62000000-0000-0000-0000-000000000002","notes":"note"}]')$s$,'P0001','assignment_exclusive_conflict');
do $$ begin assert (select count(*)=2 from public.assignment where week_plan_id='61000000-0000-0000-0000-000000000001'); end $$;
select pg_temp.save(array['62000000-0000-0000-0000-000000000003']::uuid[],
 '[{"duty_id":"62000000-0000-0000-0000-000000000001","notes":"note"},{"duty_id":"62000000-0000-0000-0000-000000000002","notes":"note"}]',notes=>' ferie ');
do $$ begin assert (select count(*)=1 and min(notes)='ferie' from public.assignment where week_plan_id='61000000-0000-0000-0000-000000000001'); end $$;

-- Verifico che un salvataggio non tocchi altri dipendenti, giorni o fasce.
select pg_temp.save(array['62000000-0000-0000-0000-000000000001']::uuid[],period=>'AFTERNOON');
select pg_temp.save(array['62000000-0000-0000-0000-000000000001']::uuid[],employee=>'60000000-0000-0000-0000-000000000005');
select pg_temp.save(array['62000000-0000-0000-0000-000000000001']::uuid[],day=>'2026-11-24');
select pg_temp.save('{}'::uuid[], '[{"duty_id":"62000000-0000-0000-0000-000000000003","notes":"ferie"}]');
do $$ begin assert (select count(*)=3 from public.assignment where week_plan_id='61000000-0000-0000-0000-000000000001'); end $$;

-- Consento la pulizia dopo una disattivazione, ma non nuove assegnazioni.
update public.user_profile set active=false where id='60000000-0000-0000-0000-000000000005';
select pg_temp.save('{}'::uuid[], '[{"duty_id":"62000000-0000-0000-0000-000000000001","notes":"note"}]',employee=>'60000000-0000-0000-0000-000000000005');
select pg_temp.expect_error($s$insert into public.assignment(week_plan_id,employee_id,date,period,duty_id) values
 ('61000000-0000-0000-0000-000000000001','60000000-0000-0000-0000-000000000002','2026-11-23','MORNING','62000000-0000-0000-0000-000000000001')$s$,'42501');
select pg_temp.expect_error('delete from public.assignment','42501');
select pg_temp.expect_error('update public.assignment set notes=notes','42501');

set local "request.jwt.claim.sub" = '60000000-0000-0000-0000-000000000002';
select pg_temp.expect_error($s$select pg_temp.save('{}'::uuid[])$s$,'42501','assignment_forbidden');
do $$ begin assert not exists(select 1 from public.assignment where week_plan_id='61000000-0000-0000-0000-000000000001'); end $$;
set local "request.jwt.claim.sub" = '60000000-0000-0000-0000-000000000004';
select pg_temp.expect_error($s$select pg_temp.save('{}'::uuid[])$s$,'42501','assignment_forbidden');
reset role;
update public.user_profile set active=false where id='60000000-0000-0000-0000-000000000001';
set local role authenticated;
set local "request.jwt.claim.sub" = '60000000-0000-0000-0000-000000000001';
select pg_temp.expect_error($s$select pg_temp.save('{}'::uuid[])$s$,'42501','assignment_forbidden');
set local role anon;
select pg_temp.expect_error($s$select pg_temp.save('{}'::uuid[])$s$,'42501');
reset role;
rollback;
select 'PASS: fasce atomiche, controlli, conflitti e permessi' as result;
