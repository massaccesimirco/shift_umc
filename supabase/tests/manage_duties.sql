-- Solo database di test: fixture annullate con ROLLBACK.
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
insert into auth.users(id, email) values
 ('10000000-0000-0000-0000-000000000001','admin@test.invalid'),
 ('10000000-0000-0000-0000-000000000002','employee@test.invalid'),
 ('10000000-0000-0000-0000-000000000003','missing@test.invalid');
insert into public.user_profile(id,first_name,last_name,email,role) values
 ('10000000-0000-0000-0000-000000000001','Admin','Test','admin@test.invalid','ADMIN'),
 ('10000000-0000-0000-0000-000000000002','Employee','Test','employee@test.invalid','EMPLOYEE');
set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000001';
insert into public.duty(name,type) values ('Test gestione','ACTIVITY');
update public.duty set name='Test rinominato', type='STATUS', exclusive=true where name='Test gestione';
update public.duty set active=false where name='Test rinominato';
do $$ begin assert (select not active from public.duty where name='Test rinominato'); end $$;
select pg_temp.expect_error($s$insert into public.duty(name,type) values (' test rinominato ','ACTIVITY')$s$,'23505');
select pg_temp.expect_error($s$insert into public.duty(name,type) values ('   ','ACTIVITY')$s$,'23514');
select pg_temp.expect_error($s$insert into public.duty(name,type) values (repeat('a',121),'ACTIVITY')$s$,'23514');
select pg_temp.expect_error($s$update public.duty set type='ACTIVITY' where name='Test rinominato'$s$,'23514');
select pg_temp.expect_error($s$update public.duty set id=gen_random_uuid()$s$,'42501');
select pg_temp.expect_error($s$delete from public.duty$s$,'42501');
update public.duty set active=true where name='Test rinominato';
reset role;
insert into public.week_plan(start_date,created_by) values ('2026-10-05','10000000-0000-0000-0000-000000000001');
insert into public.assignment(week_plan_id,employee_id,date,period,duty_id)
select w.id,'10000000-0000-0000-0000-000000000002','2026-10-05','MORNING',d.id
from public.week_plan w, public.duty d where d.name='Test rinominato';
set local role authenticated;
select pg_temp.expect_error($s$update public.duty set exclusive=false where name='Test rinominato'$s$,'P0001');
select pg_temp.expect_error($s$update public.duty set type='ACTIVITY',exclusive=false where name='Test rinominato'$s$,'P0001');
update public.duty set active=false where name='Test rinominato';
-- Il dipendente vede anche lo storico disattivato ma non può modificare.
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000002';
select pg_temp.expect_error($s$insert into public.duty(name,type) values ('Abuso','ACTIVITY')$s$,'42501');
update public.duty set active=true where name='Test rinominato';
do $$ begin assert (select not active from public.duty where name='Test rinominato'); end $$;
-- Profilo assente: insert vietato e update senza righe autorizzate.
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000003';
select pg_temp.expect_error($s$insert into public.duty(name,type) values ('Abuso','ACTIVITY')$s$,'42501');
update public.duty set active=true;
do $$ begin assert (select count(*) from public.duty)=0; end $$;
reset role;
update public.user_profile set active=false where role='ADMIN';
set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000001';
select pg_temp.expect_error($s$insert into public.duty(name,type) values ('Abuso','ACTIVITY')$s$,'42501');
update public.duty set active=true;
reset role;
do $$ begin
 assert (select not active from public.duty where name='Test rinominato');
 assert (select count(*) from public.assignment)=1;
end $$;
set local role anon;
select pg_temp.expect_error($s$insert into public.duty(name,type) values ('Abuso','ACTIVITY')$s$,'42501');
select pg_temp.expect_error($s$update public.duty set active=true$s$,'42501');
reset role;
rollback;
select 'PASS: gestione mansioni, privilegi, RLS e storico' as result;
