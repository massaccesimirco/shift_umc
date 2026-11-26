-- Salvo una fascia della bozza in una sola transazione e controllo i permessi sul server.
begin;

create function public.save_assignment_slot(
  p_week_id uuid,
  p_employee_id uuid,
  p_date date,
  p_period public.day_period,
  p_duty_ids uuid[],
  p_notes text,
  p_expected jsonb
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  w public.week_plan%rowtype;
  employee public.user_profile%rowtype;
  duty_row public.duty%rowtype;
  current_slot jsonb;
  duty_count integer := 0;
  has_exclusive boolean := false;
begin
  -- Rileggo e blocco l'attore: un'identità dichiarata nel corpo non mi autorizza.
  perform 1 from public.user_profile
    where id = auth.uid() and role = 'ADMIN' and active for share;
  if not found then
    raise exception 'assignment_forbidden' using errcode = '42501';
  end if;

  -- Serializzo le scritture sulla settimana e impedisco modifiche alle pubblicate.
  select * into w from public.week_plan where id = p_week_id for update;
  if not found or w.status <> 'DRAFT' then
    raise exception 'assignment_week_not_draft' using errcode = 'P0001';
  end if;
  if p_date is null or p_period is null or
     p_date < w.start_date or p_date > w.start_date + 4 then
    raise exception 'assignment_invalid_date' using errcode = '22023';
  end if;
  if p_duty_ids is null or cardinality(p_duty_ids) > 100 or
     array_position(p_duty_ids, null) is not null or
     cardinality(p_duty_ids) <> (select count(distinct id) from unnest(p_duty_ids) id) or
     p_notes is null or char_length(p_notes) > 2000 or
     p_expected is null or jsonb_typeof(p_expected) <> 'array' then
    raise exception 'assignment_invalid_input' using errcode = '22023';
  end if;

  select * into employee from public.user_profile where id = p_employee_id for share;
  if not found or employee.role <> 'EMPLOYEE' or
     (not employee.active and cardinality(p_duty_ids) > 0) then
    raise exception 'assignment_employee_unavailable' using errcode = 'P0001';
  end if;

  -- Confronto anche le note: non sovrascrivo una fascia cambiata dopo la lettura.
  select coalesce(jsonb_agg(jsonb_build_object('duty_id', duty_id, 'notes', notes)
    order by duty_id::text), '[]'::jsonb) into current_slot
    from public.assignment where week_plan_id = p_week_id and employee_id = p_employee_id
      and date = p_date and period = p_period;
  if current_slot is distinct from p_expected then
    raise exception 'assignment_conflict' using errcode = 'P0001';
  end if;

  -- Blocco le mansioni mentre verifico stato e regole, prima di cancellare alcuna riga.
  for duty_row in select * from public.duty where id = any(p_duty_ids) order by id for share loop
    if not duty_row.active then
      raise exception 'assignment_duty_unavailable' using errcode = 'P0001';
    end if;
    duty_count := duty_count + 1;
    has_exclusive := has_exclusive or duty_row.exclusive;
  end loop;
  if duty_count <> cardinality(p_duty_ids) then
    raise exception 'assignment_duty_unavailable' using errcode = 'P0001';
  end if;
  if has_exclusive and duty_count > 1 then
    raise exception 'assignment_exclusive_conflict' using errcode = 'P0001';
  end if;

  -- Sostituisco la fascia solo dopo i controlli; una lista vuota rimuove le assegnazioni.
  delete from public.assignment where week_plan_id = p_week_id and employee_id = p_employee_id
    and date = p_date and period = p_period;
  insert into public.assignment(week_plan_id, employee_id, date, period, duty_id, notes)
    select p_week_id, p_employee_id, p_date, p_period, id, trim(p_notes)
    from unnest(p_duty_ids) id;
end;
$$;
revoke all on function public.save_assignment_slot(uuid,uuid,date,public.day_period,uuid[],text,jsonb)
  from public, anon, authenticated;
grant execute on function public.save_assignment_slot(uuid,uuid,date,public.day_period,uuid[],text,jsonb)
  to authenticated;
-- Mantengo bloccate le scritture dirette: il client deve passare dai controlli della funzione.
comment on table public.assignment is
  'Salvo le fasce delle bozze tramite save_assignment_slot; non concedo scritture dirette ai client.';
commit;
