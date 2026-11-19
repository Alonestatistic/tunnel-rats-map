-- v4: minigames and a per-server score sheet. Run after v2 (and v3). Safe to run twice.
--
-- Every player has one points wallet per server (starts at 1000). Games are played through play_game(),
-- which rolls the result here in the database, so nobody can fake a win from their browser.
-- Server apps (Discord bots, DayZ server tools) read the sheet and give or take points through the api_* calls.
--
-- The symbol / crate tables below must match GAMES in index.html (that copy is only used for display and guest play).

create table if not exists public.game_wallets (
  server_id uuid not null references public.servers on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  points bigint not null default 1000 check (points >= 0),
  plays integer not null default 0,
  wagered bigint not null default 0,
  won bigint not null default 0,
  best_win bigint not null default 0,
  best_game text,
  airdrop_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (server_id, user_id)
);

-- notable events, newest last: jackpots, big wins, airdrops, points given by apps, resets.
-- Bots poll api_game_log to announce them.
create table if not exists public.game_log (
  id bigserial primary key,
  server_id uuid not null references public.servers on delete cascade,
  user_id uuid references public.profiles on delete cascade,
  kind text not null check (kind in ('jackpot', 'big_win', 'airdrop', 'grant', 'reset')),
  game text,
  amount bigint not null default 0,
  balance bigint,
  note text check (note is null or char_length(note) <= 200),
  created_at timestamptz not null default now()
);
create index if not exists game_log_server on public.game_log (server_id, id);

alter table public.game_wallets enable row level security;
alter table public.game_log enable row level security;
drop policy if exists "wallets: members read" on public.game_wallets;
drop policy if exists "game log: members read" on public.game_log;
create policy "wallets: members read" on public.game_wallets for select to authenticated using (srv_role(server_id) is not null);
create policy "game log: members read" on public.game_log for select to authenticated using (srv_role(server_id) is not null);
-- read-only from the browser: every change goes through the functions below
revoke insert, update, delete on public.game_wallets, public.game_log from authenticated, anon;
grant select on public.game_wallets, public.game_log to authenticated;

-- weighted pick: returns the index (0-based) into w
create or replace function public._game_roll(w int[]) returns int
language plpgsql volatile as $$
declare total int := 0; r int; i int;
begin
  for i in 1 .. array_length(w, 1) loop total := total + w[i]; end loop;
  r := floor(random() * total)::int;
  for i in 1 .. array_length(w, 1) loop
    if r < w[i] then return i - 1; end if;
    r := r - w[i];
  end loop;
  return array_length(w, 1) - 1;
end $$;

create or replace function public._game_wallet(p_server uuid, p_user uuid) returns public.game_wallets
language plpgsql security definer set search_path = public as $$
declare g game_wallets;
begin
  insert into game_wallets (server_id, user_id) values (p_server, p_user) on conflict do nothing;
  select * into g from game_wallets where server_id = p_server and user_id = p_user for update;
  return g;
end $$;
revoke all on function public._game_wallet(uuid, uuid) from public, anon, authenticated;

-- play one round. p_game: 'slots' or 'crates'. p_pick: which crate (0-2) for crates.
create or replace function public.play_game(p_server uuid, p_game text, p_bet int, p_pick int default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  g game_wallets;
  -- slots: zombie, apple, beans, rag, battery, axe, morphine, plate carrier, M4  (about 96% paid back)
  sw int[] := array[14, 16, 13, 11, 9, 7, 5, 3, 2];
  s3 int[] := array[0, 5, 10, 15, 25, 40, 80, 200, 750];   -- three of a kind, times the bet
  s2 int[] := array[0, 1, 2, 2, 4, 5, 7, 12, 25];          -- any two of a kind
  -- crates: empty, canned food, medical, car parts, backpack, plate carrier, M4  (about 94%)
  cw int[] := array[47, 16, 14, 12, 6, 4, 1];
  cm numeric[] := array[0, 0.5, 1, 2, 3, 5, 10];
  a int; b int; c int; win bigint := 0; res jsonb; picks int[];
begin
  if auth.uid() is null then raise exception 'Log in first'; end if;
  if srv_role(p_server) is null then raise exception 'Join the server first'; end if;
  if p_bet not in (10, 25, 50, 100, 250) then raise exception 'Bet 10, 25, 50, 100 or 250'; end if;
  g := _game_wallet(p_server, auth.uid());
  if g.updated_at > clock_timestamp() - interval '400 milliseconds' and g.plays > 0 then raise exception 'Slow down'; end if;
  if g.points < p_bet then raise exception 'Not enough points. Grab the airdrop or wait for it to come back.'; end if;

  if p_game = 'slots' then
    a := _game_roll(sw); b := _game_roll(sw); c := _game_roll(sw);
    if a = b and b = c then win := p_bet * s3[a + 1];
    elsif a = b or a = c then win := p_bet * s2[a + 1];
    elsif b = c then win := p_bet * s2[b + 1];
    end if;
    res := jsonb_build_object('reels', jsonb_build_array(a, b, c));
  elsif p_game = 'crates' then
    if p_pick not between 0 and 2 then raise exception 'Pick crate 0, 1 or 2'; end if;
    picks := array[_game_roll(cw), _game_roll(cw), _game_roll(cw)];
    win := floor(p_bet * cm[picks[p_pick + 1] + 1]);
    res := jsonb_build_object('crates', to_jsonb(picks), 'pick', p_pick);
  else
    raise exception 'Unknown game %', p_game;
  end if;

  update game_wallets set points = points - p_bet + win, plays = plays + 1, wagered = wagered + p_bet, won = won + win,
    best_win = greatest(best_win, win), best_game = case when win > best_win then p_game else best_game end, updated_at = clock_timestamp()
    where server_id = p_server and user_id = auth.uid() returning * into g;
  if win >= p_bet * 50 then
    insert into game_log (server_id, user_id, kind, game, amount, balance) values (p_server, auth.uid(), 'jackpot', p_game, win, g.points);
  elsif win >= p_bet * 10 then
    insert into game_log (server_id, user_id, kind, game, amount, balance) values (p_server, auth.uid(), 'big_win', p_game, win, g.points);
  end if;
  return res || jsonb_build_object('game', p_game, 'bet', p_bet, 'win', win, 'points', g.points);
end $$;

-- free points every 20 hours
create or replace function public.claim_airdrop(p_server uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g game_wallets; amt int := 250;
begin
  if auth.uid() is null then raise exception 'Log in first'; end if;
  if srv_role(p_server) is null then raise exception 'Join the server first'; end if;
  g := _game_wallet(p_server, auth.uid());
  if g.airdrop_at is not null and g.airdrop_at > now() - interval '20 hours' then
    raise exception 'The next airdrop lands %', to_char(g.airdrop_at + interval '20 hours', 'Dy HH24:MI "UTC"'); end if;
  update game_wallets set points = points + amt, airdrop_at = now(), updated_at = clock_timestamp()
    where server_id = p_server and user_id = auth.uid() returning * into g;
  insert into game_log (server_id, user_id, kind, amount, balance) values (p_server, auth.uid(), 'airdrop', amt, g.points);
  return jsonb_build_object('amount', amt, 'points', g.points, 'airdrop_at', g.airdrop_at);
end $$;

-- owner / admins: wipe the score sheet (everyone back to 1000 on their next game)
create or replace function public.reset_scores(p_server uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(srv_role(p_server), '') not in ('owner', 'admin') then raise exception 'Server admins only'; end if;
  delete from game_wallets where server_id = p_server;
  insert into game_log (server_id, user_id, kind, note) values (p_server, auth.uid(), 'reset', 'Score sheet reset');
end $$;

-- ============ API (any key on the server can read; only server-wide write keys can give points) ============
create or replace function public.api_scores(p_key text, p_limit int default 50) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k api_keys; s servers;
begin
  k := _api_key(p_key);
  select * into s from servers where id = k.server_id;
  return jsonb_build_object(
    'server', jsonb_build_object('id', s.id, 'name', s.name),
    'players', coalesce((select jsonb_agg(row_to_json(t)) from (
      select p.username, fa.tag as faction_tag, fa.name as faction, w.points, w.plays, w.wagered, w.won, w.best_win, w.best_game, w.updated_at
      from game_wallets w join profiles p on p.id = w.user_id
      left join faction_members fm on fm.server_id = w.server_id and fm.user_id = w.user_id
      left join factions fa on fa.id = fm.faction_id
      where w.server_id = k.server_id
      order by w.points desc, w.updated_at
      limit greatest(1, least(coalesce(p_limit, 50), 500))) t), '[]'));
end $$;

create or replace function public.api_game_log(p_key text, p_after bigint default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k api_keys;
begin
  k := _api_key(p_key);
  return coalesce((select jsonb_agg(row_to_json(t)) from (
    select l.id, l.kind, l.game, l.amount, l.balance, l.note, p.username, l.created_at
    from game_log l left join profiles p on p.id = l.user_id
    where l.server_id = k.server_id and l.id > coalesce(p_after, 0)
    order by l.id limit 100) t), '[]');
end $$;

create or replace function public.api_give_points(p_key text, p_username text, p_amount bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k api_keys; uid uuid; g game_wallets;
begin
  k := _api_key(p_key);
  if not k.can_write or k.faction_id is not null then raise exception 'Giving points needs a server-wide write key'; end if;
  if p_amount is null or p_amount = 0 or abs(p_amount) > 1000000 then raise exception 'p_amount must be between -1000000 and 1000000, not 0'; end if;
  select id into uid from profiles where lower(username) = lower(trim(p_username));
  if uid is null or not exists (select 1 from server_members where server_id = k.server_id and user_id = uid) then
    raise exception 'No player called % on this server', p_username; end if;
  g := _game_wallet(k.server_id, uid);
  if g.points + p_amount < 0 then raise exception '% only has % points', p_username, g.points; end if;
  update game_wallets set points = points + p_amount, updated_at = clock_timestamp()
    where server_id = k.server_id and user_id = uid returning * into g;
  insert into game_log (server_id, user_id, kind, amount, balance, note)
    values (k.server_id, uid, 'grant', p_amount, g.points, left(coalesce(nullif(trim(p_note), ''), k.label, 'API'), 200));
  return jsonb_build_object('username', p_username, 'points', g.points);
end $$;

revoke execute on function public._game_roll(int[]) from public, anon, authenticated;
grant execute on function public.play_game(uuid, text, int, int), public.claim_airdrop(uuid), public.reset_scores(uuid) to authenticated;
revoke execute on function public.play_game(uuid, text, int, int), public.claim_airdrop(uuid), public.reset_scores(uuid) from public, anon;
grant execute on function public.api_scores(text, int), public.api_game_log(text, bigint), public.api_give_points(text, text, bigint, text) to anon, authenticated;

do $$ declare t text; begin
  foreach t in array array['game_wallets', 'game_log'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
