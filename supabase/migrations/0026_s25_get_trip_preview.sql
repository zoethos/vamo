-- S25: view-before-install share preview via anon RPC (no direct table reads).
-- Numbering: 0025 reserved for S22 close notice on feature/close-report.

-- Nullable until S23 resolve-theme writes at trip creation.
alter table trips add column if not exists theme jsonb;

create or replace function s25_default_theme_pack() returns jsonb
language sql
immutable
set search_path = public
as $$
  select '{
    "id": "default",
    "label": "Vamo",
    "gradient": ["#FF5B4D", "#6A2D6F"],
    "statBackground": "#FFE6EC",
    "statPrimary": "#0C0E16",
    "statMuted": "#2A2E3A",
    "accent": "#FF5B4D",
    "memberBubble": "#FFE6EC",
    "memberInitial": "#0C0E16",
    "tagline": "Si va?"
  }'::jsonb;
$$;

create or replace function get_trip_preview(p_token text) returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_invite invites;
  v_preview jsonb;
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return null;
  end if;

  select * into v_invite from invites where token = p_token;
  if not found then
    return null;
  end if;
  if v_invite.expires_at < now() then
    return null;
  end if;
  if v_invite.uses >= v_invite.max_uses then
    return null;
  end if;

  select jsonb_build_object(
    'trip_name', t.name,
    'destination', t.destination,
    'start_date', t.start_date,
    'end_date', t.end_date,
    'member_count', (
      select count(*)::int
      from trip_members tm
      where tm.trip_id = t.id
        and tm.status = 'active'
    ),
    'theme', coalesce(t.theme, s25_default_theme_pack())
  )
  into v_preview
  from trips t
  where t.id = v_invite.trip_id;

  return v_preview;
end;
$$;

revoke all on function s25_default_theme_pack() from public;
grant execute on function s25_default_theme_pack() to postgres;

revoke all on function get_trip_preview(text) from public;
grant execute on function get_trip_preview(text) to anon;
grant execute on function get_trip_preview(text) to authenticated;
