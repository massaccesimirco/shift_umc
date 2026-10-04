-- ShiftUMC: prima migrazione
begin;

create type public.user_role as enum ('ADMIN', 'EMPLOYEE');
create type public.duty_type as enum ('ACTIVITY', 'STATUS');
create type public.week_status as enum ('DRAFT', 'PUBLISHED');
create type public.day_period as enum ('MORNING', 'AFTERNOON');

create table public.user_profile (
  id uuid primary key references auth.users(id) on delete restrict,
  first_name text not null check (length(trim(first_name)) > 0),
  last_name text not null check (length(trim(last_name)) > 0),
  email text not null check (length(trim(email)) > 0),
  role public.user_role not null default 'EMPLOYEE',
  active boolean not null default true
);
create unique index user_profile_email_unique on public.user_profile (lower(email));

create table public.duty (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  type public.duty_type not null,
  exclusive boolean not null default false,
  active boolean not null default true,
  constraint only_status_can_be_exclusive check (not exclusive or type = 'STATUS')
);
create unique index duty_name_unique on public.duty (lower(trim(name)));

create table public.week_plan (
  id uuid primary key default gen_random_uuid(),
  start_date date not null unique,
  status public.week_status not null default 'DRAFT',
  created_by uuid not null references public.user_profile(id) on delete restrict,
  created_at timestamptz not null default now(),
  published_at timestamptz,
  constraint week_starts_monday check (extract(isodow from start_date) = 1),
  constraint publication_timestamp check (
    (status = 'DRAFT' and published_at is null) or
    (status = 'PUBLISHED' and published_at is not null)
  )
);

create table public.assignment (
  id uuid primary key default gen_random_uuid(),
  week_plan_id uuid not null references public.week_plan(id) on delete restrict,
  employee_id uuid not null references public.user_profile(id) on delete restrict,
  date date not null,
  period public.day_period not null,
  duty_id uuid not null references public.duty(id) on delete restrict,
  notes text not null default '',
  constraint weekday_only check (extract(isodow from date) between 1 and 5),
  constraint unique_duty_in_slot unique (week_plan_id, employee_id, date, period, duty_id)
);
create index assignment_employee_week on public.assignment(employee_id, week_plan_id);
create index assignment_duty on public.assignment(duty_id);
create index week_plan_creator on public.week_plan(created_by);

-- Funzioni di supporto in uno schema non esposto dalle API.
-- SECURITY DEFINER consente di leggere il profilo senza ricorsione nelle RLS.
-- L'identità proviene da auth.uid(), non da un parametro passato dal client.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create function private.is_active_user() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.user_profile where id = (select auth.uid()) and active
  );
$$;
create function private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.user_profile
    where id = (select auth.uid()) and active and role = 'ADMIN'
  );
$$;
revoke all on function private.is_active_user() from public, anon, authenticated;
revoke all on function private.is_admin() from public, anon, authenticated;
grant execute on function private.is_active_user() to authenticated;
grant execute on function private.is_admin() to authenticated;

alter table public.user_profile enable row level security;
alter table public.duty enable row level security;
alter table public.week_plan enable row level security;
alter table public.assignment enable row level security;

-- Rimuove anche gli eventuali privilegi assegnati automaticamente da Supabase.
revoke all on public.user_profile, public.duty, public.week_plan, public.assignment
  from public, anon, authenticated;
grant select on public.user_profile, public.duty, public.week_plan, public.assignment
  to authenticated;

create policy profile_read on public.user_profile for select to authenticated
using ((select private.is_admin()) or
  (id = (select auth.uid()) and (select private.is_active_user())));

-- Anche una mansione disattivata deve essere leggibile nello storico.
create policy duty_read on public.duty for select to authenticated
using ((select private.is_active_user()));

create policy week_read on public.week_plan for select to authenticated
using ((select private.is_admin()) or
  (status = 'PUBLISHED' and (select private.is_active_user())));

create policy assignment_read on public.assignment for select to authenticated
using ((select private.is_admin()) or (
  employee_id = (select auth.uid()) and (select private.is_active_user()) and
  exists (select 1 from public.week_plan w
    where w.id = assignment.week_plan_id and w.status = 'PUBLISHED')
));

comment on table public.user_profile is
  'Profilo applicativo collegato a Supabase Auth. Nessuna password. Disattivazione invece di cancellazione.';
comment on table public.assignment is
  'Una riga per mansione nella fascia. Scritture client bloccate finché non saranno implementate le operazioni validate.';

commit;
