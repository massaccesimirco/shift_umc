-- Verifico pubblicazione e visibilità su un database isolato con le migrazioni 001–007.
begin;
set local plpgsql.check_asserts = on;
create function pg_temp.expect_error(statement text, expected_code text, expected_message text default null)
returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then
    if sqlstate=expected_code and (expected_message is null or sqlerrm=expected_message) then return; end if;
    raise;
  end;
  raise exception 'Operazione accettata erroneamente: %',statement;
end;
$$;
insert into auth.users(id,email) values
 ('70000000-0000-0000-0000-000000000001','admin@publish-test.invalid'),
 ('70000000-0000-0000-0000-000000000002','anna@publish-test.invalid'),
 ('70000000-0000-0000-0000-000000000003','mario@publish-test.invalid'),
 ('70000000-0000-0000-0000-000000000004','missing@publish-test.invalid');
insert into public.user_profile(id,first_name,last_name,email,role,active) values
 ('70000000-0000-0000-0000-000000000001','Admin','Uno','admin@publish-test.invalid','ADMIN',true),
 ('70000000-0000-0000-0000-000000000002','Anna','Verdi','anna@publish-test.invalid','EMPLOYEE',true),
 ('70000000-0000-0000-0000-000000000003','Mario','Rossi','mario@publish-test.invalid','EMPLOYEE',true);
insert into public.week_plan(id,start_date,created_by) values
 ('71000000-0000-0000-0000-000000000001','2026-11-23','70000000-0000-0000-0000-000000000001'),
 ('71000000-0000-0000-0000-000000000002','2026-11-30','70000000-0000-0000-0000-000000000001');
insert into public.duty(id,name,type,exclusive) values
 ('72000000-0000-0000-0000-000000000001','Sportello test pubblicazione','ACTIVITY',false),
 ('72000000-0000-0000-0000-000000000002','Ferie test pubblicazione','STATUS',true);

create function pg_temp.snapshot(w uuid) returns jsonb language sql as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'notes',notes) order by id::text),'[]'::jsonb)
 from public.assignment where week_plan_id=w;
$$;
create function pg_temp.publish_current() returns void language sql as $$
 select public.publish_week('71000000-0000-0000-0000-000000000001',
   pg_temp.snapshot('71000000-0000-0000-0000-000000000001'));
$$;

set local role authenticated;
set local "request.jwt.claim.sub"='70000000-0000-0000-0000-000000000001';
select pg_temp.expect_error('select pg_temp.publish_current()','P0001','publication_empty');
select pg_temp.expect_error($s$select public.publish_week('71000000-0000-0000-0000-000000000099','[]')$s$,'P0001','publication_week_missing');
select pg_temp.expect_error($s$select public.publish_week('71000000-0000-0000-0000-000000000001',null)$s$,'P0001','publication_conflict');
select public.save_assignment_slot('71000000-0000-0000-0000-000000000001',
 '70000000-0000-0000-0000-000000000002','2026-11-23','MORNING',
 array['72000000-0000-0000-0000-000000000001']::uuid[],'nota Anna','[]');
select public.save_assignment_slot('71000000-0000-0000-0000-000000000001',
 '70000000-0000-0000-0000-000000000003','2026-11-23','MORNING',
 array['72000000-0000-0000-0000-000000000001']::uuid[],'nota Mario','[]');
select pg_temp.expect_error($s$select public.publish_week('71000000-0000-0000-0000-000000000001','[]')$s$,'P0001','publication_conflict');

-- Verifico che la disattivazione tra salvataggio e pubblicazione richieda una correzione.
update public.user_profile set active=false where id='70000000-0000-0000-0000-000000000003';
select pg_temp.expect_error('select pg_temp.publish_current()','P0001','publication_invalid_assignments');
update public.user_profile set active=true where id='70000000-0000-0000-0000-000000000003';
update public.duty set active=false where id='72000000-0000-0000-0000-000000000001';
select pg_temp.expect_error('select pg_temp.publish_current()','P0001','publication_invalid_assignments');
update public.duty set active=true where id='72000000-0000-0000-0000-000000000001';

-- Simulo dati legacy non validi come proprietario; la funzione deve respingerli ugualmente.
reset role;
insert into public.assignment(id,week_plan_id,employee_id,date,period,duty_id) values
 ('73000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002','2026-11-30','MORNING','72000000-0000-0000-0000-000000000001');
set local role authenticated;
select pg_temp.expect_error('select pg_temp.publish_current()','P0001','publication_invalid_assignments');
reset role;
delete from public.assignment where id='73000000-0000-0000-0000-000000000001';
insert into public.assignment(id,week_plan_id,employee_id,date,period,duty_id) values
 ('73000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002','2026-11-23','MORNING','72000000-0000-0000-0000-000000000002');
set local role authenticated;
select pg_temp.expect_error('select pg_temp.publish_current()','P0001','publication_invalid_assignments');
reset role;
delete from public.assignment where id='73000000-0000-0000-0000-000000000001';

-- Prima della pubblicazione, il dipendente non legge né il contenitore né le assegnazioni.
set local role authenticated;
set local "request.jwt.claim.sub"='70000000-0000-0000-0000-000000000002';
do $$ begin
 assert not exists(select 1 from public.week_plan where id='71000000-0000-0000-0000-000000000001');
 assert not exists(select 1 from public.assignment where week_plan_id='71000000-0000-0000-0000-000000000001');
end $$;
select pg_temp.expect_error('select pg_temp.publish_current()','42501','publication_forbidden');
set local "request.jwt.claim.sub"='70000000-0000-0000-0000-000000000004';
select pg_temp.expect_error('select pg_temp.publish_current()','42501','publication_forbidden');
set local "request.jwt.claim.sub"='70000000-0000-0000-0000-000000000001';
select pg_temp.publish_current();
do $$ begin
 assert (select status='PUBLISHED' and published_at is not null from public.week_plan where id='71000000-0000-0000-0000-000000000001');
end $$;
-- Verifico la ripetibilità della richiesta dopo un'eventuale risposta persa.
select public.publish_week('71000000-0000-0000-0000-000000000001','[]');
select pg_temp.expect_error($s$select public.save_assignment_slot('71000000-0000-0000-0000-000000000001',
 '70000000-0000-0000-0000-000000000002','2026-11-23','MORNING','{}'::uuid[],'','[]')$s$,'P0001','assignment_week_not_draft');
select pg_temp.expect_error($s$update public.week_plan set status='DRAFT',published_at=null$s$,'42501');

-- Verifico lo storico: una mansione disattivata dopo la pubblicazione rimane leggibile.
update public.duty set active=false where id='72000000-0000-0000-0000-000000000001';
set local "request.jwt.claim.sub"='70000000-0000-0000-0000-000000000002';
do $$ begin
 assert (select count(*)=1 from public.week_plan where id in ('71000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000002'));
 assert (select count(*)=1 from public.assignment where week_plan_id='71000000-0000-0000-0000-000000000001');
 assert not exists(select 1 from public.assignment where employee_id='70000000-0000-0000-0000-000000000003');
 assert (select name='Sportello test pubblicazione' from public.duty where id='72000000-0000-0000-0000-000000000001');
end $$;
reset role;
update public.user_profile set active=false where id='70000000-0000-0000-0000-000000000001';
set local role authenticated;
set local "request.jwt.claim.sub"='70000000-0000-0000-0000-000000000001';
select pg_temp.expect_error('select pg_temp.publish_current()','42501','publication_forbidden');
set local role anon;
select pg_temp.expect_error('select pg_temp.publish_current()','42501');
reset role;
rollback;
select 'PASS: pubblicazione controllata, blocco modifiche e visibilità personale' as result;
