-- Profile avatar preferences: keep uploaded avatar storage while allowing users
-- to display initials/aliases instead of the photo.

alter table public.profiles
  add column if not exists avatar_display_mode text not null default 'photo',
  add column if not exists avatar_initials text;

alter table public.profiles
  drop constraint if exists profiles_avatar_display_mode_check;

alter table public.profiles
  add constraint profiles_avatar_display_mode_check
  check (avatar_display_mode in ('photo', 'initials'));

alter table public.profiles
  drop constraint if exists profiles_avatar_initials_check;

alter table public.profiles
  add constraint profiles_avatar_initials_check
  check (
    avatar_initials is null
    or char_length(btrim(avatar_initials)) between 1 and 4
  );
