-- Mi annoto il caso da verificare: Database di test: applicare prima tutte e quattro le migrazioni.
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
 ('10000000-0000-0000-0000-000000000001','admin@week-test.invalid'),
 ('10000000-0000-0000-0000-000000000002','employee@week-test.invalid'),
 ('10000000-0000-0000-0000-000000000003','missing@week-test.invalid');
insert into public.user_profile(id,first_name,last_name,email,role) values
 ('10000000-0000-0000-0000-000000000001','Admin','Uno','admin@week-test.invalid','ADMIN'),
 ('10000000-0000-0000-0000-000000000002','Anna','Verdi','employee@week-test.invalid','EMPLOYEE');

set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000001';
insert into public.week_plan(start_date,created_by) values ('2026-10-05',auth.uid());
do $$ begin
 assert (select count(*) from public.week_plan)=1;
 assert (select status='DRAFT' and published_at is null and created_by=auth.uid() and created_at is not null from public.week_plan);
end $$;
select pg_temp.expect_error($s$insert into public.week_plan(start_date,created_by) values ('2026-10-05',auth.uid())$s$,'23505');
select pg_temp.expect_error($s$insert into public.week_plan(start_date,created_by) values ('2026-10-06',auth.uid())$s$,'23514');
select pg_temp.expect_error($s$insert into public.week_plan(start_date,created_by) values ('2026-10-12','10000000-0000-0000-0000-000000000002')$s$,'42501');
select pg_temp.expect_error($s$insert into public.week_plan(start_date,created_by,status,published_at) values ('2026-10-12',auth.uid(),'PUBLISHED',now())$s$,'42501');
select pg_temp.expect_error($s$insert into public.week_plan(start_date,created_by,created_at) values ('2026-10-12',auth.uid(),'2020-01-01')$s$,'42501');
select pg_temp.expect_error($s$insert into public.week_plan(id,start_date,created_by) values (gen_random_uuid(),'2026-10-12',auth.uid())$s$,'42501');
select pg_temp.expect_error($s$update public.week_plan set status='PUBLISHED',published_at=now()$s$,'42501');
select pg_temp.expect_error($s$delete from public.week_plan$s$,'42501');

-- Mi annoto il caso da verificare: Il dipendente non vede la bozza e non può creare settimane.
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000002';
do $$ begin assert (select count(*) from public.week_plan)=0; end $$;
select pg_temp.expect_error($s$insert into public.week_plan(start_date,created_by) values ('2026-10-12',auth.uid())$s$,'42501');
-- Mi annoto il caso da verificare: Neppure un account senza profilo o un amministratore disattivato.
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000003';
select pg_temp.expect_error($s$insert into public.week_plan(start_date,created_by) values ('2026-10-12',auth.uid())$s$,'42501');
reset role;
update public.user_profile set active=false where role='ADMIN';
set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-0000-0000-000000000001';
do $$ begin assert (select count(*) from public.week_plan)=0; end $$;
select pg_temp.expect_error($s$insert into public.week_plan(start_date,created_by) values ('2026-10-12',auth.uid())$s$,'42501');
reset role;
set local role anon;
select pg_temp.expect_error($s$select * from public.week_plan$s$,'42501');
select pg_temp.expect_error($s$insert into public.week_plan(start_date,created_by) values ('2026-10-12','10000000-0000-0000-0000-000000000001')$s$,'42501');
reset role;
rollback;
select 'PASS: creazione bozze, autore, unicità e permessi' as result;
