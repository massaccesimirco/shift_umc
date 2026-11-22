-- Mi annoto il caso da verificare: Database di test con le migrazioni 001–005 applicate.
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
 ('10000000-0000-0000-0000-000000000001','admin@create-test.invalid');
insert into public.user_profile(id,first_name,last_name,email,role) values
 ('10000000-0000-0000-0000-000000000001','Admin','Uno','admin@create-test.invalid','ADMIN');
-- Mi annoto il caso da verificare: Account creato dal server: profilo generato e ruolo sempre EMPLOYEE.
insert into auth.users(id,email) values
 ('10000000-0000-0000-0000-000000000002','Anna@create-test.invalid');
update auth.users set raw_app_meta_data =
 '{"shiftumc_employee":{"first_name":" Anna ","last_name":" Verdi ","created_by":"10000000-0000-0000-0000-000000000001","role":"ADMIN"}}'
 where id='10000000-0000-0000-0000-000000000002';
do $$ begin
 assert (select first_name='Anna' and last_name='Verdi' and role='EMPLOYEE' and active and email='anna@create-test.invalid' from public.user_profile where id='10000000-0000-0000-0000-000000000002');
end $$;
-- Mi annoto il caso da verificare: Un aggiornamento successivo non riscrive i nomi gestiti nell'app.
update public.user_profile set first_name='Maria' where id='10000000-0000-0000-0000-000000000002';
update auth.users set raw_app_meta_data = raw_app_meta_data || '{"extra":"value"}'::jsonb
 where id='10000000-0000-0000-0000-000000000002';
do $$ begin assert (select first_name='Maria' from public.user_profile where id='10000000-0000-0000-0000-000000000002'); end $$;
-- Mi annoto il caso da verificare: I metadata controllabili dall'utente non attivano il trigger.
insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000003','self@create-test.invalid',
 '{"shiftumc_employee":{"first_name":"Fake","last_name":"Admin","created_by":"10000000-0000-0000-0000-000000000001"}}');
do $$ begin assert not exists(select 1 from public.user_profile where id='10000000-0000-0000-0000-000000000003'); end $$;
-- Mi annoto il caso da verificare: Un fallimento del profilo annulla anche l'inserimento dell'account.
select pg_temp.expect_error($s$do $block$ begin
 insert into auth.users(id,email) values
 ('10000000-0000-0000-0000-000000000004','invalid@create-test.invalid');
 update auth.users set raw_app_meta_data =
 '{"shiftumc_employee":{"first_name":"","last_name":"Verdi","created_by":"10000000-0000-0000-0000-000000000001"}}'
 where id='10000000-0000-0000-0000-000000000004';
end $block$ $s$, '23514');
do $$ begin assert not exists(select 1 from auth.users where id='10000000-0000-0000-0000-000000000004'); end $$;
select pg_temp.expect_error($s$insert into auth.users(id,email,raw_app_meta_data) values
 ('10000000-0000-0000-0000-000000000004','anna@create-test.invalid',
 '{"shiftumc_employee":{"first_name":"Anna","last_name":"Verdi","created_by":"10000000-0000-0000-0000-000000000001"}}')$s$, '23505');
-- Mi annoto il caso da verificare: Dipendente e amministratore disattivato non sono autori validi.
select pg_temp.expect_error($s$insert into auth.users(id,email,raw_app_meta_data) values
 ('10000000-0000-0000-0000-000000000004','invalid@create-test.invalid',
 '{"shiftumc_employee":{"first_name":"Anna","last_name":"Verdi","created_by":"10000000-0000-0000-0000-000000000002"}}')$s$, '42501');
update public.user_profile set active=false where id='10000000-0000-0000-0000-000000000001';
select pg_temp.expect_error($s$insert into auth.users(id,email,raw_app_meta_data) values
 ('10000000-0000-0000-0000-000000000004','invalid@create-test.invalid',
 '{"shiftumc_employee":{"first_name":"Anna","last_name":"Verdi","created_by":"10000000-0000-0000-0000-000000000001"}}')$s$, '42501');
set local role authenticated;
select pg_temp.expect_error($s$insert into public.user_profile(id,first_name,last_name,email) values
 ('10000000-0000-0000-0000-000000000003','Fake','User','self@create-test.invalid')$s$, '42501');
select pg_temp.expect_error('select private.create_employee_profile()', '42501');
reset role;
rollback;
select 'PASS: profilo atomico, ruolo fisso e metadata protetti' as result;
