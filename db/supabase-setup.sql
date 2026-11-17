-- Run this once in your Supabase project: SQL Editor -> New query -> paste -> Run.

create table if not exists public.map_features (
  id text primary key,
  room text not null,
  data jsonb not null,
  updated_at timestamptz not null default now()
);

create index if not exists map_features_room_idx on public.map_features (room);

-- Needed so other players see deletions live.
alter table public.map_features replica identity full;

-- Anyone holding the site's key can read/write rows. The faction code
-- (the "room") is what keeps factions apart, so keep it private.
alter table public.map_features enable row level security;

drop policy if exists "faction map access" on public.map_features;
create policy "faction map access" on public.map_features
  for all to anon using (true) with check (true);

grant select, insert, update, delete on public.map_features to anon;

-- Turn on live updates for this table.
alter publication supabase_realtime add table public.map_features;
