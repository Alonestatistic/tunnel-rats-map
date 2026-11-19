-- v4: Loot merge, the on-map minigame, and a per-server leaderboard. Run after v2 (and v3). Safe to run twice.
--
-- Loot drops onto the map. Drag one item onto an identical one and they merge into the next item up the chain.
-- Two top items make 🚁 heli crash loot; two heli crashes clear for a big bonus. Every merge is one "upgrade";
-- the leaderboard ranks players by upgrades. Points come from merges, with bonuses for combos, ✨ shiny items
-- and the first time you make each item.
--
-- The board lives here and every merge is checked here, so nobody can fake upgrades or points from their browser.
-- Server apps (Discord bots, DayZ server tools) read the leaderboard and give or take points through the api_* calls.
--
-- Off by default: a server owner or admin switches it on for their server (servers.games, in the Server tab),
-- and then each player still chooses to show the Games tab.
--
-- The item chains and numbers below must match MERGE in index.html (that copy is only used for display and guest play).

-- an earlier draft of this file had slots and crates; remove them if they were ever created
drop function if exists public.play_game(uuid, text, int, int);
drop function if exists public.claim_airdrop(uuid);
drop function if exists public._game_wallet(uuid, uuid);
drop function if exists public._game_roll(int[]);
drop table if exists public.game_wallets;

alter table public.servers add column if not exists games boolean not null default false;

create table if not exists public.game_players (
  server_id uuid not null references public.servers on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  -- items on the board: [{"i": id, "c": chain 0-2 (3 = heli), "t": tier 0-6, "s": shiny}]
  board jsonb not null default '[]',
  next_id integer not null default 1,
  spawn_at timestamptz not null default now() - interval '40 seconds',   -- 8 items waiting on your first game
  points bigint not null default 0 check (points >= 0),
  merges integer not null default 0,
  helis integer not null default 0,
  best_tier integer not null default 0,
  best_item text,
  found integer not null default 0,     -- bit per item made at least once (discovery bonus)
  combo integer not null default 0,
  last_merge_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (server_id, user_id)
);

-- notable events, newest last: heli crashes made, heli crashes cleared, points given by apps, resets.
-- Bots poll api_game_log to announce them.
create table if not exists public.game_log (
  id bigserial primary key,
  server_id uuid not null references public.servers on delete cascade,
  user_id uuid references public.profiles on delete cascade,
  kind text not null,
  game text,
  amount bigint not null default 0,
  balance bigint,
  note text check (note is null or char_length(note) <= 200),
  created_at timestamptz not null default now()
);
delete from public.game_log where kind not in ('heli', 'clear', 'grant', 'reset');
alter table public.game_log drop constraint if exists game_log_kind_check;
alter table public.game_log add constraint game_log_kind_check check (kind in ('heli', 'clear', 'grant', 'reset'));
create index if not exists game_log_server on public.game_log (server_id, id);

alter table public.game_players enable row level security;
alter table public.game_log enable row level security;
drop policy if exists "players: members read" on public.game_players;
drop policy if exists "game log: members read" on public.game_log;
create policy "players: members read" on public.game_players for select to authenticated using (srv_role(server_id) is not null);
create policy "game log: members read" on public.game_log for select to authenticated using (srv_role(server_id) is not null);
-- read-only from the browser: every change goes through the functions below
revoke insert, update, delete on public.game_players, public.game_log from authenticated, anon;
grant select on public.game_players, public.game_log to authenticated;

create or replace function public._merge_player(p_server uuid, p_user uuid) returns public.game_players
language plpgsql security definer set search_path = public as $$
declare g game_players;
begin
  insert into game_players (server_id, user_id) values (p_server, p_user) on conflict do nothing;
  select * into g from game_players where server_id = p_server and user_id = p_user for update;
  return g;
end $$;

-- drop new loot: one item every 5 seconds, at most 20 on the board, at most 10 saved up while you're away.
-- Returns the new items.
create or replace function public._merge_fill(p_server uuid, p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g game_players; cnt int; n int; k int; since timestamptz; added jsonb := '[]';
begin
  g := _merge_player(p_server, p_user);
  cnt := jsonb_array_length(g.board);
  since := greatest(g.spawn_at, clock_timestamp() - interval '50 seconds');
  n := least(floor(extract(epoch from clock_timestamp() - since) / 5)::int, 20 - cnt);
  if n <= 0 then
    -- a full board doesn't save up drops
    if cnt >= 20 then update game_players set spawn_at = clock_timestamp() where server_id = p_server and user_id = p_user; end if;
    return added;
  end if;
  for k in 0 .. n - 1 loop
    added := added || jsonb_build_array(jsonb_build_object('i', g.next_id + k, 'c', floor(random() * 3)::int,
      't', case when random() < 0.2 then 1 else 0 end, 's', random() < 0.07));
  end loop;
  update game_players set board = board || added, next_id = next_id + n,
    spawn_at = case when cnt + n >= 20 then clock_timestamp() else since + make_interval(secs => n * 5) end
    where server_id = p_server and user_id = p_user;
  return added;
end $$;
revoke all on function public._merge_player(uuid, uuid), public._merge_fill(uuid, uuid) from public, anon, authenticated;

-- your board and stats (drops any loot that's due)
create or replace function public.merge_state(p_server uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g game_players;
begin
  if auth.uid() is null then raise exception 'Log in first'; end if;
  if srv_role(p_server) is null then raise exception 'Join the server first'; end if;
  if not coalesce((select games from servers where id = p_server), false) then raise exception 'Loot merge is switched off on this server'; end if;
  perform _merge_fill(p_server, auth.uid());
  select * into g from game_players where server_id = p_server and user_id = auth.uid();
  return jsonb_build_object('board', g.board, 'points', g.points, 'merges', g.merges, 'helis', g.helis, 'best_tier', g.best_tier,
    'found', g.found, 'combo', g.combo, 'last_merge_at', g.last_merge_at);
end $$;

-- merge item p_b into item p_a (both must be the same item)
create or replace function public.merge_items(p_server uuid, p_a int, p_b int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  -- chain 0 medical, 1 weapons, 2 gear; tiers 0-5, then tier 6 is heli crash loot for every chain
  names text[] := array['Rag', 'Bandage', 'Painkillers', 'Morphine', 'Blood bag', 'First aid kit',
                        'Stone', 'Kitchen knife', 'Hatchet', 'Crossbow', 'Pistol', 'Scoped rifle',
                        'Wool socks', 'Cap', 'Hiking boots', 'Backpack', 'Plate carrier', 'Ballistic helmet'];
  g game_players; ea jsonb; eb jsonb; c int; t int; nt int; nc int; bit int := 0;
  v_combo int; mult numeric; shiny boolean; base int; bonus int := 0; gain bigint; item jsonb := null; nm text;
  v_board jsonb; spawned jsonb;
begin
  if auth.uid() is null then raise exception 'Log in first'; end if;
  if srv_role(p_server) is null then raise exception 'Join the server first'; end if;
  if not coalesce((select games from servers where id = p_server), false) then raise exception 'Loot merge is switched off on this server'; end if;
  g := _merge_player(p_server, auth.uid());
  if p_a = p_b then raise exception 'Pick two different items'; end if;
  select e into ea from jsonb_array_elements(g.board) e where (e->>'i')::int = p_a;
  select e into eb from jsonb_array_elements(g.board) e where (e->>'i')::int = p_b;
  if ea is null or eb is null then raise exception 'That item is gone'; end if;
  c := (ea->>'c')::int; t := (ea->>'t')::int;
  if c <> (eb->>'c')::int or t <> (eb->>'t')::int then raise exception 'Only two of the same item can be merged'; end if;

  v_combo := case when g.last_merge_at > clock_timestamp() - interval '6 seconds' then least(g.combo + 1, 8) else 0 end;
  shiny := coalesce((ea->>'s')::boolean, false) or coalesce((eb->>'s')::boolean, false);
  mult := (1 + 0.25 * v_combo) * case when shiny then 2 else 1 end;
  v_board := coalesce((select jsonb_agg(e) from jsonb_array_elements(g.board) e where (e->>'i')::int not in (p_a, p_b)), '[]');

  if t = 6 then
    -- two heli crashes: cleared, big bonus
    base := 2500; nt := 7; nm := 'Heli crash cleared';
  else
    nt := t + 1; nc := case when nt = 6 then 3 else c end;
    base := 10 * (2 ^ nt)::int;
    nm := case when nt = 6 then 'Heli crash loot' else names[c * 6 + nt + 1] end;
    bit := case when nt = 6 then 1 << 18 else 1 << (c * 6 + nt) end;
    if g.found & bit = 0 then bonus := case when nt = 6 then 500 else 50 * nt end; end if;
    item := jsonb_build_object('i', g.next_id, 'c', nc, 't', nt, 's', false);
    v_board := v_board || jsonb_build_array(item);
  end if;
  gain := floor(base * mult) + bonus;

  update game_players set board = v_board, points = points + gain, merges = merges + 1,
    helis = helis + case when nt = 6 then 1 else 0 end,
    best_item = case when nt > best_tier or best_item is null then nm else best_item end,
    best_tier = greatest(best_tier, nt), found = game_players.found | bit, combo = v_combo,
    last_merge_at = clock_timestamp(), next_id = next_id + case when item is null then 0 else 1 end, updated_at = clock_timestamp()
    where server_id = p_server and user_id = auth.uid() returning * into g;
  if nt = 6 then
    insert into game_log (server_id, user_id, kind, game, amount, balance) values (p_server, auth.uid(), 'heli', 'merge', gain, g.points);
  elsif nt = 7 then
    insert into game_log (server_id, user_id, kind, game, amount, balance) values (p_server, auth.uid(), 'clear', 'merge', gain, g.points);
  end if;
  spawned := _merge_fill(p_server, auth.uid());
  return jsonb_build_object('item', item, 'name', nm, 'gain', gain, 'base', base, 'combo', v_combo, 'shiny', shiny, 'bonus', bonus,
    'points', g.points, 'merges', g.merges, 'spawned', spawned);
end $$;

-- owner / admins: wipe the leaderboard (everyone starts over on their next game)
create or replace function public.reset_scores(p_server uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(srv_role(p_server), '') not in ('owner', 'admin') then raise exception 'Server admins only'; end if;
  delete from game_players where server_id = p_server;
  insert into game_log (server_id, user_id, kind, note) values (p_server, auth.uid(), 'reset', 'Leaderboard reset');
end $$;

-- ============ API (any key on the server can read; only server-wide write keys can give points) ============
drop function if exists public.api_scores(text, int);
create or replace function public.api_scores(p_key text, p_limit int default 50) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k api_keys; s servers;
begin
  k := _api_key(p_key);
  select * into s from servers where id = k.server_id;
  return jsonb_build_object(
    'server', jsonb_build_object('id', s.id, 'name', s.name),
    'players', coalesce((select jsonb_agg(row_to_json(t)) from (
      select p.username, fa.tag as faction_tag, fa.name as faction, w.merges as upgrades, w.points, w.helis, w.best_item, w.updated_at
      from game_players w join profiles p on p.id = w.user_id
      left join faction_members fm on fm.server_id = w.server_id and fm.user_id = w.user_id
      left join factions fa on fa.id = fm.faction_id
      where w.server_id = k.server_id
      order by w.merges desc, w.points desc, w.updated_at
      limit greatest(1, least(coalesce(p_limit, 50), 500))) t), '[]'));
end $$;

create or replace function public.api_game_log(p_key text, p_after bigint default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k api_keys;
begin
  k := _api_key(p_key);
  return coalesce((select jsonb_agg(row_to_json(t)) from (
    select l.id, l.kind, l.amount, l.balance, l.note, p.username, l.created_at
    from game_log l left join profiles p on p.id = l.user_id
    where l.server_id = k.server_id and l.id > coalesce(p_after, 0)
    order by l.id limit 100) t), '[]');
end $$;

create or replace function public.api_give_points(p_key text, p_username text, p_amount bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k api_keys; uid uuid; g game_players;
begin
  k := _api_key(p_key);
  if not k.can_write or k.faction_id is not null then raise exception 'Giving points needs a server-wide write key'; end if;
  if p_amount is null or p_amount = 0 or abs(p_amount) > 1000000 then raise exception 'p_amount must be between -1000000 and 1000000, not 0'; end if;
  select id into uid from profiles where lower(username) = lower(trim(p_username));
  if uid is null or not exists (select 1 from server_members where server_id = k.server_id and user_id = uid) then
    raise exception 'No player called % on this server', p_username; end if;
  g := _merge_player(k.server_id, uid);
  if g.points + p_amount < 0 then raise exception '% only has % points', p_username, g.points; end if;
  update game_players set points = points + p_amount, updated_at = clock_timestamp()
    where server_id = k.server_id and user_id = uid returning * into g;
  insert into game_log (server_id, user_id, kind, amount, balance, note)
    values (k.server_id, uid, 'grant', p_amount, g.points, left(coalesce(nullif(trim(p_note), ''), k.label, 'API'), 200));
  return jsonb_build_object('username', p_username, 'points', g.points);
end $$;

grant execute on function public.merge_state(uuid), public.merge_items(uuid, int, int), public.reset_scores(uuid) to authenticated;
revoke execute on function public.merge_state(uuid), public.merge_items(uuid, int, int), public.reset_scores(uuid) from public, anon;
grant execute on function public.api_scores(text, int), public.api_game_log(text, bigint), public.api_give_points(text, text, bigint, text) to anon, authenticated;

do $$ declare t text; begin
  foreach t in array array['game_players', 'game_log'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
