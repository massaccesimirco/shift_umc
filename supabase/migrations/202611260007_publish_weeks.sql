-- Pubblico una bozza solo dopo avere ricontrollato i dati e la fotografia confermata.
begin;
create function public.publish_week(p_week_id uuid, p_expected jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  w public.week_plan%rowtype;
  snapshot jsonb;
begin
  perform 1 from public.user_profile
    where id=auth.uid() and role='ADMIN' and active for share;
  if not found then
    raise exception 'publication_forbidden' using errcode='42501';
  end if;
  -- Uso lo stesso blocco del salvataggio fasce per coordinare pubblicazione e modifiche.
  select * into w from public.week_plan where id=p_week_id for update;
  if not found then
    raise exception 'publication_week_missing' using errcode='P0001';
  end if;
  -- Rendo innocuo un secondo invio dopo una risposta persa, senza cambiare la data.
  if w.status='PUBLISHED' then return; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'notes',notes) order by id::text),'[]'::jsonb)
    into snapshot from public.assignment where week_plan_id=p_week_id;
  if p_expected is null or jsonb_typeof(p_expected)<>'array' or snapshot is distinct from p_expected then
    raise exception 'publication_conflict' using errcode='P0001';
  end if;
  if jsonb_array_length(snapshot)=0 then
    raise exception 'publication_empty' using errcode='P0001';
  end if;
  -- Mantengo stabili i profili e le mansioni controllati fino al commit.
  perform 1 from public.user_profile where id in
    (select employee_id from public.assignment where week_plan_id=p_week_id)
    order by id for share;
  perform 1 from public.duty where id in
    (select duty_id from public.assignment where week_plan_id=p_week_id)
    order by id for share;
  if exists (
    select 1 from public.assignment a
    join public.user_profile e on e.id=a.employee_id
    join public.duty d on d.id=a.duty_id
    where a.week_plan_id=p_week_id and
      (not e.active or e.role<>'EMPLOYEE' or not d.active or
       a.date<w.start_date or a.date>w.start_date+4 or char_length(a.notes)>2000)
  ) or exists (
    select 1 from public.assignment a join public.duty d on d.id=a.duty_id
    where a.week_plan_id=p_week_id
    group by a.employee_id,a.date,a.period having count(*)>1 and bool_or(d.exclusive)
  ) then
    raise exception 'publication_invalid_assignments' using errcode='P0001';
  end if;
  update public.week_plan set status='PUBLISHED',published_at=now() where id=p_week_id;
end;
$$;
revoke all on function public.publish_week(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.publish_week(uuid,jsonb) to authenticated;
-- Non concedo UPDATE diretto: le settimane pubblicate restano bloccate per il client.
commit;
