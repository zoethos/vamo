-- Product signals — suggest-a-feature (spec section 8b, layer 4).
-- Private submissions: users insert and read only their own. No public board in Wave 1.

create table if not exists suggestions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 500),
  category    text not null default 'other'
              check (category in ('trips', 'money', 'sharing', 'other')),
  app_version text,
  platform    text,
  status      text not null default 'new'
              check (status in ('new', 'reviewed', 'planned', 'shipped', 'declined')),
  created_at  timestamptz not null default now()
);
create index if not exists idx_suggestions_user on suggestions(user_id);
create index if not exists idx_suggestions_status on suggestions(status, created_at);

alter table suggestions enable row level security;

-- Insert your own only; user_id must be the caller.
create policy suggestions_insert_own on suggestions for insert
  with check (auth.uid() = user_id);

-- Read your own only (e.g. "your suggestions" list later). Triage happens
-- via the service role / dashboard, which bypasses RLS.
create policy suggestions_select_own on suggestions for select
  using (auth.uid() = user_id);

-- No update/delete policies: submissions are immutable from the client;
-- status changes are an operator action (service role).
