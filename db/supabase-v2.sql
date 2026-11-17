-- Faction Map v2: accounts, servers, factions, invites, shared markers, notes and API keys.
-- Run once in Supabase -> SQL Editor. Safe to re-run (drops and recreates functions/policies, keeps data).
-- The old v1 table (map_features) is left alone so old markers can be imported.

create extension if not exists pgcrypto with schema extensions;

-- ============ tables ============
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  username text not null check (username ~ '^[A-Za-z0-9_.-]{3,20}$'),
  created_at timestamptz not null default now()
);
create unique index if not exists profiles_username_lower on public.profiles (lower(username));

create table if not exists public.servers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 60),
  map text not null default 'nasdara' check (map ~ '^[A-Za-z0-9_-]{2,40}$'),
  join_code text not null unique default upper(substr(md5(gen_random_uuid()::text), 1, 8)),
  owner uuid not null references public.profiles on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.server_members (
  server_id uuid not null references public.servers on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at timestamptz not null default now(),
  primary key (server_id, user_id)
);

create table if not exists public.factions (
  id uuid primary key default gen_random_uuid(),
  server_id uuid not null references public.servers on delete cascade,
  name text not null check (char_length(name) between 2 and 40),
  tag text check (tag is null or char_length(tag) <= 6),
  color text check (color is null or color ~ '^#[0-9a-fA-F]{6}$'),
  flag text check (flag is null or flag ~ '^[A-Za-z0-9_]{1,30}$'),
  invite_code text not null unique default upper(substr(md5(gen_random_uuid()::text), 1, 8)),
  created_by uuid references public.profiles on delete set null,
  created_at timestamptz not null default now(),
  unique (server_id, name)
);

create table if not exists public.faction_members (
  faction_id uuid not null references public.factions on delete cascade,
  server_id uuid not null references public.servers on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  role text not null default 'member' check (role in ('leader', 'officer', 'member')),
  joined_at timestamptz not null default now(),
  primary key (faction_id, user_id),
  unique (server_id, user_id)            -- one faction per player per server
);

create table if not exists public.faction_invites (
  faction_id uuid not null references public.factions on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  invited_by uuid references public.profiles on delete set null,
  created_at timestamptz not null default now(),
  primary key (faction_id, user_id)
);

create table if not exists public.features (
  id text primary key check (char_length(id) between 8 and 64),
  server_id uuid not null references public.servers on delete cascade,
  faction_id uuid references public.factions on delete cascade,
  owner uuid references public.profiles on delete set null,
  vis text not null default 'faction' check (vis in ('private', 'faction', 'server')),
  map text not null,
  data jsonb not null check (pg_column_size(data) < 400000),
  updated_at timestamptz not null default now()
);
create index if not exists features_server_map on public.features (server_id, map);

create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  feature_id text not null references public.features on delete cascade,
  server_id uuid not null references public.servers on delete cascade,
  faction_id uuid references public.factions on delete cascade,
  author uuid not null references public.profiles on delete cascade,
  vis text not null check (vis in ('private', 'crew', 'server')),
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists notes_feature on public.notes (feature_id);
create index if not exists notes_server on public.notes (server_id);

create table if not exists public.api_keys (
  id uuid primary key default gen_random_uuid(),
  key_hash text not null unique,
  prefix text not null,
  server_id uuid not null references public.servers on delete cascade,
  faction_id uuid references public.factions on delete cascade,
  label text check (label is null or char_length(label) <= 60),
  can_write boolean not null default false,
  created_by uuid references public.profiles on delete set null,
  created_at timestamptz not null default now(),
  last_used timestamptz
);

-- ============ helpers (security definer so policies don't recurse) ============
create or replace function public.srv_role(sid uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from server_members where server_id = sid and user_id = auth.uid()
$$;
create or replace function public.my_faction(sid uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select faction_id from faction_members where server_id = sid and user_id = auth.uid()
$$;
create or replace function public.fac_role(fid uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from faction_members where faction_id = fid and user_id = auth.uid()
$$;

-- new auth user -> profile (username comes from sign-up metadata)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username) values (new.id, new.raw_user_meta_data ->> 'username');
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- features: owner, server and creation time can't be changed by an update
create or replace function public.features_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'UPDATE' then
    new.owner := old.owner; new.server_id := old.server_id;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists features_guard on public.features;
create trigger features_guard before insert or update on public.features for each row execute function public.features_guard();

create or replace function public.notes_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'UPDATE' then
    new.author := old.author; new.feature_id := old.feature_id; new.server_id := old.server_id;
    new.faction_id := old.faction_id; new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists notes_guard on public.notes;
create trigger notes_guard before insert or update on public.notes for each row execute function public.notes_guard();

-- ============ row level security ============
alter table public.profiles enable row level security;
alter table public.servers enable row level security;
alter table public.server_members enable row level security;
alter table public.factions enable row level security;
alter table public.faction_members enable row level security;
alter table public.faction_invites enable row level security;
alter table public.features enable row level security;
alter table public.notes enable row level security;
alter table public.api_keys enable row level security;

do $$ declare r record; begin
  for r in select policyname, tablename from pg_policies where schemaname = 'public'
    and tablename in ('profiles','servers','server_members','factions','faction_members','faction_invites','features','notes','api_keys')
  loop execute format('drop policy %I on public.%I', r.policyname, r.tablename); end loop;
end $$;

create policy "profiles readable" on public.profiles for select to authenticated using (true);

create policy "servers: members read" on public.servers for select to authenticated using (srv_role(id) is not null);
create policy "servers: admins edit" on public.servers for update to authenticated
  using (srv_role(id) in ('owner', 'admin')) with check (srv_role(id) in ('owner', 'admin'));
create policy "servers: owner deletes" on public.servers for delete to authenticated using (owner = auth.uid());

create policy "members: read" on public.server_members for select to authenticated using (srv_role(server_id) is not null);
create policy "members: leave or kick" on public.server_members for delete to authenticated
  using (role <> 'owner' and (user_id = auth.uid() or srv_role(server_id) in ('owner', 'admin')));
create policy "members: owner sets roles" on public.server_members for update to authenticated
  using (srv_role(server_id) = 'owner' and role <> 'owner') with check (role in ('admin', 'member'));

create policy "factions: read" on public.factions for select to authenticated using (srv_role(server_id) is not null);
create policy "factions: leaders edit" on public.factions for update to authenticated
  using (fac_role(id) in ('leader', 'officer') or srv_role(server_id) in ('owner', 'admin'))
  with check (fac_role(id) in ('leader', 'officer') or srv_role(server_id) in ('owner', 'admin'));
create policy "factions: leader or admin deletes" on public.factions for delete to authenticated
  using (fac_role(id) = 'leader' or srv_role(server_id) in ('owner', 'admin'));

create policy "fmembers: read" on public.faction_members for select to authenticated using (srv_role(server_id) is not null);
create policy "fmembers: kick" on public.faction_members for delete to authenticated
  using (fac_role(faction_id) = 'leader' and user_id <> auth.uid()
      or fac_role(faction_id) = 'officer' and role = 'member');
create policy "fmembers: leader sets roles" on public.faction_members for update to authenticated
  using (fac_role(faction_id) = 'leader' and user_id <> auth.uid()) with check (role in ('leader', 'officer', 'member'));

create policy "invites: read" on public.faction_invites for select to authenticated
  using (user_id = auth.uid() or fac_role(faction_id) in ('leader', 'officer'));
create policy "invites: officers send" on public.faction_invites for insert to authenticated
  with check (invited_by = auth.uid() and fac_role(faction_id) in ('leader', 'officer'));
create policy "invites: decline or cancel" on public.faction_invites for delete to authenticated
  using (user_id = auth.uid() or fac_role(faction_id) in ('leader', 'officer'));

create policy "features: read" on public.features for select to authenticated using (
  srv_role(server_id) is not null and (
    vis = 'server' or owner = auth.uid() or (vis = 'faction' and faction_id = my_faction(server_id))));
create policy "features: add" on public.features for insert to authenticated with check (
  owner = auth.uid() and srv_role(server_id) is not null
  and (faction_id is null or faction_id = my_faction(server_id))
  and (vis <> 'faction' or faction_id is not null));
create policy "features: edit" on public.features for update to authenticated using (
  owner = auth.uid()
  or (vis in ('faction', 'server') and faction_id is not null and faction_id = my_faction(server_id))
  or (vis = 'server' and srv_role(server_id) in ('owner', 'admin'))
) with check (
  srv_role(server_id) is not null
  and (vis <> 'faction' or faction_id is not null)
  and (faction_id is null or faction_id = my_faction(server_id) or srv_role(server_id) in ('owner', 'admin')));
create policy "features: delete" on public.features for delete to authenticated using (
  owner = auth.uid()
  or (vis in ('faction', 'server') and faction_id is not null and faction_id = my_faction(server_id))
  or (vis = 'server' and srv_role(server_id) in ('owner', 'admin')));

create policy "notes: read" on public.notes for select to authenticated using (
  author = auth.uid()
  or (vis = 'crew' and faction_id is not null and faction_id = my_faction(server_id))
  or (vis = 'server' and srv_role(server_id) is not null));
create policy "notes: add" on public.notes for insert to authenticated with check (
  author = auth.uid() and srv_role(server_id) is not null
  and exists (select 1 from public.features f where f.id = feature_id and f.server_id = notes.server_id)
  and (vis <> 'crew' or (faction_id is not null and faction_id = my_faction(server_id))));
create policy "notes: edit own" on public.notes for update to authenticated using (author = auth.uid()) with check (author = auth.uid());
create policy "notes: delete" on public.notes for delete to authenticated using (
  author = auth.uid() or (vis = 'server' and srv_role(server_id) in ('owner', 'admin')));

create policy "api keys: read" on public.api_keys for select to authenticated using (
  (faction_id is null and srv_role(server_id) in ('owner', 'admin'))
  or (faction_id is not null and fac_role(faction_id) in ('leader', 'officer')));
create policy "api keys: revoke" on public.api_keys for delete to authenticated using (
  (faction_id is null and srv_role(server_id) in ('owner', 'admin'))
  or (faction_id is not null and fac_role(faction_id) in ('leader', 'officer')));

grant select, insert, update, delete on public.profiles, public.servers, public.server_members, public.factions,
  public.faction_members, public.faction_invites, public.features, public.notes, public.api_keys to authenticated;

-- ============ actions (RPC) ============
create or replace function public.username_available(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from profiles where lower(username) = lower(p_name))
$$;

create or replace function public.create_server(p_name text, p_map text) returns public.servers
language plpgsql security definer set search_path = public as $$
declare s servers;
begin
  if auth.uid() is null then raise exception 'Log in first'; end if;
  if (select count(*) from servers where owner = auth.uid()) >= 10 then raise exception 'You already own 10 servers'; end if;
  insert into servers (name, map, owner) values (trim(p_name), coalesce(nullif(p_map, ''), 'nasdara'), auth.uid()) returning * into s;
  insert into server_members (server_id, user_id, role) values (s.id, auth.uid(), 'owner');
  return s;
end $$;

create or replace function public.join_server(p_code text) returns public.servers
language plpgsql security definer set search_path = public as $$
declare s servers;
begin
  if auth.uid() is null then raise exception 'Log in first'; end if;
  select * into s from servers where join_code = upper(trim(p_code));
  if s.id is null then raise exception 'No server with that code'; end if;
  insert into server_members (server_id, user_id) values (s.id, auth.uid()) on conflict do nothing;
  return s;
end $$;

create or replace function public.create_faction(p_server uuid, p_name text, p_tag text, p_color text, p_flag text) returns public.factions
language plpgsql security definer set search_path = public as $$
declare f factions;
begin
  if srv_role(p_server) is null then raise exception 'Join the server first'; end if;
  if my_faction(p_server) is not null then raise exception 'Leave your current faction first'; end if;
  insert into factions (server_id, name, tag, color, flag, created_by)
    values (p_server, trim(p_name), nullif(trim(p_tag), ''), nullif(p_color, ''), nullif(p_flag, ''), auth.uid()) returning * into f;
  insert into faction_members (faction_id, server_id, user_id, role) values (f.id, p_server, auth.uid(), 'leader');
  return f;
end $$;

create or replace function public._join_faction(f factions) returns public.factions
language plpgsql security definer set search_path = public as $$
declare cur uuid;
begin
  insert into server_members (server_id, user_id) values (f.server_id, auth.uid()) on conflict do nothing;
  cur := my_faction(f.server_id);
  if cur = f.id then return f; end if;
  if cur is not null then raise exception 'Leave your current faction first'; end if;
  insert into faction_members (faction_id, server_id, user_id, role)
    values (f.id, f.server_id, auth.uid(),
      case when exists (select 1 from faction_members where faction_id = f.id) then 'member' else 'leader' end);
  delete from faction_invites where faction_id = f.id and user_id = auth.uid();
  return f;
end $$;
revoke all on function public._join_faction(public.factions) from public, anon, authenticated;

create or replace function public.join_faction(p_code text) returns public.factions
language plpgsql security definer set search_path = public as $$
declare f factions;
begin
  if auth.uid() is null then raise exception 'Log in first'; end if;
  select * into f from factions where invite_code = upper(trim(p_code));
  if f.id is null then raise exception 'No faction with that invite code'; end if;
  return _join_faction(f);
end $$;

create or replace function public.accept_invite(p_faction uuid) returns public.factions
language plpgsql security definer set search_path = public as $$
declare f factions;
begin
  if not exists (select 1 from faction_invites where faction_id = p_faction and user_id = auth.uid()) then
    raise exception 'That invite no longer exists'; end if;
  select * into f from factions where id = p_faction;
  return _join_faction(f);
end $$;

create or replace function public.invite_user(p_faction uuid, p_username text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid;
begin
  if coalesce(fac_role(p_faction), '') not in ('leader', 'officer') then raise exception 'Only leaders and officers can invite'; end if;
  select id into uid from profiles where lower(username) = lower(trim(p_username));
  if uid is null then raise exception 'No player called %', p_username; end if;
  if exists (select 1 from faction_members where faction_id = p_faction and user_id = uid) then raise exception 'Already in your faction'; end if;
  insert into faction_invites (faction_id, user_id, invited_by) values (p_faction, uid, auth.uid()) on conflict do nothing;
end $$;

create or replace function public.leave_faction(p_server uuid) returns void
language plpgsql security definer set search_path = public as $$
declare fid uuid; was text; nxt uuid;
begin
  select faction_id, role into fid, was from faction_members where server_id = p_server and user_id = auth.uid();
  if fid is null then return; end if;
  delete from faction_members where faction_id = fid and user_id = auth.uid();
  if was = 'leader' and not exists (select 1 from faction_members where faction_id = fid and role = 'leader') then
    select user_id into nxt from faction_members where faction_id = fid
      order by (role = 'officer') desc, joined_at limit 1;
    if nxt is not null then update faction_members set role = 'leader' where faction_id = fid and user_id = nxt; end if;
  end if;
end $$;

create or replace function public.leave_server(p_server uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if srv_role(p_server) = 'owner' then raise exception 'The owner cannot leave. Delete the server instead.'; end if;
  perform leave_faction(p_server);
  delete from server_members where server_id = p_server and user_id = auth.uid();
end $$;

create or replace function public.new_code(p_kind text, p_id uuid) returns text
language plpgsql security definer set search_path = public as $$
declare c text := upper(substr(md5(gen_random_uuid()::text), 1, 8));
begin
  if p_kind = 'server' then
    if coalesce(srv_role(p_id), '') not in ('owner', 'admin') then raise exception 'Admins only'; end if;
    update servers set join_code = c where id = p_id;
  else
    if coalesce(fac_role(p_id), '') not in ('leader', 'officer') then raise exception 'Leaders and officers only'; end if;
    update factions set invite_code = c where id = p_id;
  end if;
  return c;
end $$;

-- ============ API keys (for bots, Discord, other apps) ============
create or replace function public.create_api_key(p_server uuid, p_faction uuid, p_label text, p_write boolean) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare k text := 'fmk_' || encode(gen_random_bytes(24), 'hex');
begin
  if p_faction is null then
    if coalesce(srv_role(p_server), '') not in ('owner', 'admin') then raise exception 'Server admins only'; end if;
  else
    if coalesce(fac_role(p_faction), '') not in ('leader', 'officer') then raise exception 'Faction leaders and officers only'; end if;
    if not exists (select 1 from factions where id = p_faction and server_id = p_server) then raise exception 'Faction not on this server'; end if;
  end if;
  insert into api_keys (key_hash, prefix, server_id, faction_id, label, can_write, created_by)
    values (encode(digest(k, 'sha256'), 'hex'), left(k, 10), p_server, p_faction, nullif(trim(p_label), ''), coalesce(p_write, false), auth.uid());
  return k;
end $$;

create or replace function public._api_key(p_key text) returns public.api_keys
language plpgsql security definer set search_path = public, extensions as $$
declare r api_keys;
begin
  select * into r from api_keys where key_hash = encode(digest(coalesce(p_key, ''), 'sha256'), 'hex');
  if r.id is null then raise exception 'Invalid API key' using errcode = '28000'; end if;
  update api_keys set last_used = now() where id = r.id and (last_used is null or last_used < now() - interval '1 minute');
  return r;
end $$;
revoke all on function public._api_key(text) from public, anon, authenticated;

create or replace function public.api_map(p_key text, p_map text default null, p_notes boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k api_keys; s servers;
begin
  k := _api_key(p_key);
  select * into s from servers where id = k.server_id;
  return jsonb_build_object(
    'server', jsonb_build_object('id', s.id, 'name', s.name, 'map', s.map),
    'scope', case when k.faction_id is null then 'server' else 'faction' end,
    'faction', (select jsonb_build_object('id', id, 'name', name, 'tag', tag, 'flag', flag, 'color', color) from factions where id = k.faction_id),
    'factions', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'tag', tag, 'flag', flag, 'color', color)) from factions where server_id = s.id), '[]'),
    'features', coalesce((
      select jsonb_agg(jsonb_build_object('id', f.id, 'vis', f.vis, 'map', f.map, 'faction_id', f.faction_id,
        'owner', (select username from profiles where id = f.owner), 'updated_at', f.updated_at, 'data', f.data,
        'notes', case when p_notes then (
          select coalesce(jsonb_agg(jsonb_build_object('vis', n.vis, 'body', n.body, 'author', (select username from profiles where id = n.author), 'created_at', n.created_at) order by n.created_at), '[]')
          from notes n where n.feature_id = f.id and (n.vis = 'server' or (n.vis = 'crew' and k.faction_id is not null and n.faction_id = k.faction_id))
        ) end) order by f.updated_at desc)
      from features f
      where f.server_id = k.server_id and (p_map is null or f.map = p_map)
        and (f.vis = 'server' or (f.vis = 'faction' and k.faction_id is not null and f.faction_id = k.faction_id))), '[]'));
end $$;

create or replace function public.api_upsert(p_key text, p_feature jsonb, p_vis text default 'faction', p_map text default null) returns text
language plpgsql security definer set search_path = public as $$
declare k api_keys; s servers; fid text := p_feature ->> 'id'; ex features; v text := coalesce(p_vis, 'faction');
begin
  k := _api_key(p_key);
  if not k.can_write then raise exception 'This API key is read-only'; end if;
  if fid is null or char_length(fid) < 8 then raise exception 'feature.id (8+ chars) is required'; end if;
  if v not in ('faction', 'server') then raise exception 'vis must be faction or server'; end if;
  if v = 'faction' and k.faction_id is null then raise exception 'Server keys can only write vis=server'; end if;
  select * into s from servers where id = k.server_id;
  select * into ex from features where id = fid;
  if ex.id is not null and (ex.server_id <> k.server_id or (k.faction_id is not null and ex.faction_id is distinct from k.faction_id)
     or ex.vis = 'private') then raise exception 'Not allowed to change that feature'; end if;
  insert into features (id, server_id, faction_id, owner, vis, map, data)
    values (fid, k.server_id, k.faction_id, k.created_by, v, coalesce(p_map, ex.map, s.map), p_feature)
    on conflict (id) do update set vis = excluded.vis, map = excluded.map, data = excluded.data;
  return fid;
end $$;

create or replace function public.api_delete(p_key text, p_id text) returns boolean
language plpgsql security definer set search_path = public as $$
declare k api_keys;
begin
  k := _api_key(p_key);
  if not k.can_write then raise exception 'This API key is read-only'; end if;
  delete from features where id = p_id and server_id = k.server_id and vis <> 'private'
    and (k.faction_id is null and vis = 'server' or faction_id = k.faction_id);
  return found;
end $$;

grant execute on function public.username_available(text), public.api_map(text, text, boolean),
  public.api_upsert(text, jsonb, text, text), public.api_delete(text, text) to anon, authenticated;
grant execute on function public.create_server(text, text), public.join_server(text), public.create_faction(uuid, text, text, text, text),
  public.join_faction(text), public.accept_invite(uuid), public.invite_user(uuid, text), public.leave_faction(uuid),
  public.leave_server(uuid), public.new_code(text, uuid), public.create_api_key(uuid, uuid, text, boolean) to authenticated;
revoke execute on function public.create_server(text, text), public.join_server(text), public.create_faction(uuid, text, text, text, text),
  public.join_faction(text), public.accept_invite(uuid), public.invite_user(uuid, text), public.leave_faction(uuid),
  public.leave_server(uuid), public.new_code(text, uuid), public.create_api_key(uuid, uuid, text, boolean) from public, anon;

-- ============ realtime ============
do $$ declare t text; begin
  foreach t in array array['features','notes','factions','faction_members','faction_invites','server_members','servers'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
