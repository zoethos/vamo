-- S44 — user-set trip hero background (separate from trip_photos / Memories)

alter table trips
  add column if not exists background_path text;

-- Private bucket: {user_id}/{trip_id}/background.{ext}
insert into storage.buckets (id, name, public)
values ('trip-backgrounds', 'trip-backgrounds', false)
on conflict (id) do update set public = false;

do $$ begin
  create policy trip_backgrounds_select on storage.objects
    for select to authenticated
    using (
      bucket_id = 'trip-backgrounds'
      and public.is_trip_member(((storage.foldername(name))[2])::uuid)
    );
exception when duplicate_object then null;
end $$;

do $$ begin
  create policy trip_backgrounds_insert on storage.objects
    for insert to authenticated
    with check (
      bucket_id = 'trip-backgrounds'
      and (storage.foldername(name))[1] = auth.uid()::text
      and public.is_trip_member(((storage.foldername(name))[2])::uuid)
      and public.is_trip_writable(((storage.foldername(name))[2])::uuid)
    );
exception when duplicate_object then null;
end $$;

do $$ begin
  create policy trip_backgrounds_update on storage.objects
    for update to authenticated
    using (
      bucket_id = 'trip-backgrounds'
      and (storage.foldername(name))[1] = auth.uid()::text
    );
exception when duplicate_object then null;
end $$;

do $$ begin
  create policy trip_backgrounds_delete on storage.objects
    for delete to authenticated
    using (
      bucket_id = 'trip-backgrounds'
      and (storage.foldername(name))[1] = auth.uid()::text
    );
exception when duplicate_object then null;
end $$;

create or replace function set_trip_background(
  p_trip_id uuid,
  p_background_path text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not is_trip_member(p_trip_id) then
    raise exception 'not a trip member';
  end if;
  if not is_trip_writable(p_trip_id) then
    raise exception 'trip is read-only';
  end if;
  update trips
  set background_path = p_background_path
  where id = p_trip_id;
end;
$$;

revoke all on function set_trip_background(uuid, text) from public;
grant execute on function set_trip_background(uuid, text) to authenticated;
