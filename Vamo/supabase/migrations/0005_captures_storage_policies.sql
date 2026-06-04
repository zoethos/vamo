-- Slice 8 review — private captures bucket with member-scoped Storage RLS.
-- Path convention: {user_id}/{trip_id}/{photo_id}.{ext}

insert into storage.buckets (id, name, public)
values ('captures', 'captures', false)
on conflict (id) do update set public = false;

do $$ begin
  create policy captures_select on storage.objects
    for select to authenticated
    using (
      bucket_id = 'captures'
      and public.is_trip_member(((storage.foldername(name))[2])::uuid)
    );
exception when duplicate_object then null;
end $$;

do $$ begin
  create policy captures_insert on storage.objects
    for insert to authenticated
    with check (
      bucket_id = 'captures'
      and (storage.foldername(name))[1] = auth.uid()::text
      and public.is_trip_member(((storage.foldername(name))[2])::uuid)
    );
exception when duplicate_object then null;
end $$;

do $$ begin
  create policy captures_update on storage.objects
    for update to authenticated
    using (
      bucket_id = 'captures'
      and (storage.foldername(name))[1] = auth.uid()::text
    );
exception when duplicate_object then null;
end $$;

do $$ begin
  create policy captures_delete on storage.objects
    for delete to authenticated
    using (
      bucket_id = 'captures'
      and (storage.foldername(name))[1] = auth.uid()::text
    );
exception when duplicate_object then null;
end $$;
