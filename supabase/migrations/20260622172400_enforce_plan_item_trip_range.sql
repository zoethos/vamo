-- Plan item dates must stay inside the parent trip date range.
-- Existing invalid dates are cleared so stale rows stop creating impossible
-- timeline days on clients that have already synced them.

update public.trip_plan_items as p
set
  starts_at = case
    when p.starts_at is not null
      and (
        (t.start_date is not null and (p.starts_at at time zone 'UTC')::date < t.start_date)
        or (coalesce(t.end_date, t.start_date) is not null
          and (p.starts_at at time zone 'UTC')::date > coalesce(t.end_date, t.start_date))
      )
      then null
    else p.starts_at
  end,
  ends_at = case
    when p.ends_at is not null
      and (
        (t.start_date is not null and (p.ends_at at time zone 'UTC')::date < t.start_date)
        or (coalesce(t.end_date, t.start_date) is not null
          and (p.ends_at at time zone 'UTC')::date > coalesce(t.end_date, t.start_date))
        or (p.starts_at is not null and p.ends_at < p.starts_at)
      )
      then null
    else p.ends_at
  end,
  updated_at = now()
from public.trips as t
where p.trip_id = t.id
  and (
    (p.starts_at is not null
      and (
        (t.start_date is not null and (p.starts_at at time zone 'UTC')::date < t.start_date)
        or (coalesce(t.end_date, t.start_date) is not null
          and (p.starts_at at time zone 'UTC')::date > coalesce(t.end_date, t.start_date))
      ))
    or (p.ends_at is not null
      and (
        (t.start_date is not null and (p.ends_at at time zone 'UTC')::date < t.start_date)
        or (coalesce(t.end_date, t.start_date) is not null
          and (p.ends_at at time zone 'UTC')::date > coalesce(t.end_date, t.start_date))
        or (p.starts_at is not null and p.ends_at < p.starts_at)
      ))
  );

create or replace function public.trip_plan_items_enforce_trip_range()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_start date;
  v_end date;
begin
  select start_date, coalesce(end_date, start_date)
  into v_start, v_end
  from public.trips
  where id = new.trip_id;

  if new.starts_at is not null and new.ends_at is not null
     and new.ends_at < new.starts_at then
    raise exception using
      errcode = '23514',
      message = 'plan item end date is before start date';
  end if;

  if new.starts_at is not null then
    if v_start is not null and (new.starts_at at time zone 'UTC')::date < v_start then
      raise exception using
        errcode = '23514',
        message = 'plan item starts_at is outside the trip date range';
    end if;
    if v_end is not null and (new.starts_at at time zone 'UTC')::date > v_end then
      raise exception using
        errcode = '23514',
        message = 'plan item starts_at is outside the trip date range';
    end if;
  end if;

  if new.ends_at is not null then
    if v_start is not null and (new.ends_at at time zone 'UTC')::date < v_start then
      raise exception using
        errcode = '23514',
        message = 'plan item ends_at is outside the trip date range';
    end if;
    if v_end is not null and (new.ends_at at time zone 'UTC')::date > v_end then
      raise exception using
        errcode = '23514',
        message = 'plan item ends_at is outside the trip date range';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trip_plan_items_enforce_trip_range_trg
  on public.trip_plan_items;

create trigger trip_plan_items_enforce_trip_range_trg
  before insert or update of trip_id, starts_at, ends_at
  on public.trip_plan_items
  for each row
  execute function public.trip_plan_items_enforce_trip_range();
