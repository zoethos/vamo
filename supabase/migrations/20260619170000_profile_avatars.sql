-- S47 — private profile avatars bucket (Horizon A, P0 + fix-up).
--
-- Privacy tier: avatars are treated the same as display_name — any authenticated user
-- may read them (mirrors profiles_read in 0001). If that tier tightens, tighten here too.
-- Owner DELETE is allowed so "Use initials" can remove the stored image (P1 retention).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  false,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = 2097152,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

do $$ begin
  create policy avatars_select on storage.objects
    for select to authenticated
    using (bucket_id = 'avatars');
exception when duplicate_object then null;
end $$;

do $$ begin
  create policy avatars_insert on storage.objects
    for insert to authenticated
    with check (
      bucket_id = 'avatars'
      and (storage.foldername(name))[1] = auth.uid()::text
    );
exception when duplicate_object then null;
end $$;

do $$ begin
  create policy avatars_update on storage.objects
    for update to authenticated
    using (
      bucket_id = 'avatars'
      and (storage.foldername(name))[1] = auth.uid()::text
    );
exception when duplicate_object then null;
end $$;

do $$ begin
  create policy avatars_delete on storage.objects
    for delete to authenticated
    using (
      bucket_id = 'avatars'
      and (storage.foldername(name))[1] = auth.uid()::text
    );
exception when duplicate_object then null;
end $$;

-- profiles.avatar_url must point at the owner's folder (or be null).
create or replace function profiles_avatar_url_guard() returns trigger
language plpgsql as $$
begin
  if new.avatar_url is not null
     and new.avatar_url not like new.id::text || '/profile%' then
    raise exception 'avatar_url must be null or under the user''s own folder';
  end if;
  return new;
end $$;

drop trigger if exists profiles_avatar_url_guard_trg on profiles;
create trigger profiles_avatar_url_guard_trg
  before insert or update on profiles
  for each row execute function profiles_avatar_url_guard();
