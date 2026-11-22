-- Mi annoto il caso da verificare: Eseguire solo in un database di test con tutte e tre le migrazioni applicate.
begin;
set local plpgsql.check_asserts = on;
create or replace function pg_temp.expect_error(statement text, expected_code text)
returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then
    if sqlstate = expected_code then return; end if;
    raise;
  end;
  raise exception 'Operazione accettata erroneamente: %', statement;
end;
$$;
insert into auth.users(id,email) values
 ('10000000-0000-0000-0000-000000000001','admin@employee-test.invalid'),
 ('10000000-0000-0000-0000-000000000002','employee@employee-test.invalid'),
 ('10000000-0000-0000-0000-000000000003','other@employee-test.invalid'),
 ('10000000-0000-0000-0000-000000000004','missing@employee-test.invalid');
insert into public.user_profile(id,first_name,last_name,email,role) values
 ('10000000-0000-0000-0000-000000000001','Admin','Uno','admin@employee-test.invalid','ADMIN'),
 ('10000000-0000-0000-0000-000000000002','Mario','Rossi','employee@employee-test.invalid','EMPLOYEE'),
 ('10000000-0000-0000-0000-000000000003','Admin','Due','other@employee-test.invalid','ADMIN');
insert into public.duty(id,name,type) values
 ('20000000-0000-0000-0000-000000000001','Mansione test dipendenti','ACTIVITY');
insert into public.week_plan(id,start_date,status,created_by,published_at) values
 ('30000000-0000-0000-0000-000000000001','2026-10-05','PUBLISHED','10000000-0000-0000-0000-000000000001',now());
insert into public.assignment(week_plan_id,employee_id,date,period,duty_id) values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','2026-10-05','MORNING','20000000-0000-0000-0000-000000000001');

set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000001';
update public.user_profile set first_name='Anna',last_name='Verdi' where role='EMPLOYEE';
do $$ begin assert (select first_name='Anna' and last_name='Verdi' from public.user_profile where role='EMPLOYEE'); end $$;
select pg_temp.expect_error($s$update public.user_profile set first_name=' ' where role='EMPLOYEE'$s$,'23514');
select pg_temp.expect_error($s$update public.user_profile set last_name=repeat('a',121) where role='EMPLOYEE'$s$,'23514');
select pg_temp.expect_error($s$update public.user_profile set role='ADMIN' where role='EMPLOYEE'$s$,'42501');
select pg_temp.expect_error($s$update public.user_profile set email='changed@test.invalid' where role='EMPLOYEE'$s$,'42501');
select pg_temp.expect_error($s$update public.user_profile set id=gen_random_uuid() where role='EMPLOYEE'$s$,'42501');
select pg_temp.expect_error($s$delete from public.user_profile where role='EMPLOYEE'$s$,'42501');
select pg_temp.expect_error($s$insert into public.user_profile(id,first_name,last_name,email) values ('10000000-0000-0000-0000-000000000004','No','Insert','missing@test.invalid')$s$,'42501');
-- Mi annoto il caso da verificare: Nessun admin può essere modificato, compreso chi esegue l'operazione.
do $$ declare n integer; begin
 update public.user_profile set active=false,first_name='Vietato' where role='ADMIN';
 get diagnostics n=row_count; assert n=0;
end $$;
update public.user_profile set active=false where role='EMPLOYEE';
do $$ begin
 assert (select not active from public.user_profile where role='EMPLOYEE');
 assert (select count(*) from public.assignment)=1;
end $$;
-- Mi annoto il caso da verificare: Sessione dipendente ancora valida, ma nessun accesso ai dati dopo disattivazione.
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000002';
do $$ declare n integer; begin
 assert (select count(*) from public.user_profile)=0;
 assert (select count(*) from public.assignment)=0;
 assert (select count(*) from public.week_plan)=0;
 assert (select count(*) from public.duty)=0;
 update public.user_profile set active=true where id=auth.uid();
 get diagnostics n=row_count; assert n=0;
end $$;
-- Mi annoto il caso da verificare: Riattivazione: stessi dati e storico.
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000001';
update public.user_profile set active=true where role='EMPLOYEE';
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000002';
do $$ declare n integer; begin
 assert (select count(*) from public.user_profile)=1;
 assert (select count(*) from public.assignment)=1;
 update public.user_profile set first_name='Abuso',active=false;
 get diagnostics n=row_count; assert n=0;
end $$;
select pg_temp.expect_error($s$update public.user_profile set role='ADMIN' where id=auth.uid()$s$,'42501');
-- Mi annoto il caso da verificare: Account senza profilo e amministratore disattivato: update di zero righe.
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000004';
do $$ declare n integer; begin
 update public.user_profile set active=false; get diagnostics n=row_count; assert n=0;
end $$;
reset role;
update public.user_profile set active=false where id='10000000-0000-0000-0000-000000000001';
set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000001';
do $$ declare n integer; begin
 update public.user_profile set active=false where role='EMPLOYEE'; get diagnostics n=row_count; assert n=0;
end $$;
reset role;
do $$ begin assert (select active and first_name='Anna' from public.user_profile where role='EMPLOYEE'); end $$;
set local role anon;
select pg_temp.expect_error($s$update public.user_profile set active=false$s$,'42501');
reset role;
rollback;
select 'PASS: gestione dipendenti, ruoli protetti e storico conservato' as result;
