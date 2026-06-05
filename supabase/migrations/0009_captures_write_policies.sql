-- Slice 14 review — captures write policies require trip membership + owner.
-- Read/insert policies from 0005 are unchanged.

drop policy if exists captures_update on storage.objects;
drop policy if exists captures_delete on storage.objects;

create policy captures_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'captures'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_trip_member(((storage.foldername(name))[2])::uuid)
  );

create policy captures_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'captures'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_trip_member(((storage.foldername(name))[2])::uuid)
  );

-- Trip owner may revoke membership (ex-member storage write smoke + Vamigos).
create policy members_owner_update on trip_members for update
  using (
    exists (
      select 1 from trips t
      where t.id = trip_id and t.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from trips t
      where t.id = trip_id and t.owner_id = auth.uid()
    )
  );
