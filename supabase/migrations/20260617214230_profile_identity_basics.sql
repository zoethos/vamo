-- Profile identity basics.
-- Keep public profile data minimal: display name + existing avatar/currency.
-- Phone/address remain intentionally out of scope because profiles_read is broad.

alter table public.profiles
  add column if not exists display_name_set_at timestamptz;

update public.profiles
set display_name_set_at = coalesce(display_name_set_at, created_at, now())
where display_name_set_at is null
  and nullif(btrim(display_name), '') is not null
  and btrim(display_name) <> 'Vamigo';

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_display_name text := nullif(btrim(new.raw_user_meta_data->>'display_name'), '');
begin
  insert into public.profiles (id, display_name, display_name_set_at)
  values (
    new.id,
    coalesce(v_display_name, 'Vamigo'),
    case
      when v_display_name is null or v_display_name = 'Vamigo' then null
      else now()
    end
  )
  on conflict (id) do nothing;
  return new;
end $$;
