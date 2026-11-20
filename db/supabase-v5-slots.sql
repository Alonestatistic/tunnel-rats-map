-- v5: Heli Crash Slots, a 5-reel, 3-row slot machine with 20 paylines. Run after v4. Safe to run twice.
--
-- It plays with the same points as Loot merge (game_players.points), so points earned by merging (or given by server
-- apps) can be bet here. Every spin is rolled here in the database, so nobody can fake a win from their browser.
-- Like Loot merge it only works on servers where an owner / admin has switched games on (servers.games).
--
-- Symbols, weights, paylines and pays below must match SLOTS in index.html (that copy is only used for display and
-- practice play). Tuned to pay back about 96% over the long run.

alter table public.game_players add column if not exists slot_free integer not null default 0;     -- free spins left
alter table public.game_players add column if not exists slot_lines integer not null default 20;   -- lines / bet the free spins use
alter table public.game_players add column if not exists slot_bet integer not null default 1;
alter table public.game_players add column if not exists slot_spins integer not null default 0;
alter table public.game_players add column if not exists slot_won bigint not null default 0;
alter table public.game_players add column if not exists slot_best bigint not null default 0;

alter table public.game_log drop constraint if exists game_log_kind_check;
alter table public.game_log add constraint game_log_kind_check check (kind in ('heli', 'clear', 'grant', 'reset', 'jackpot', 'big_win'));

-- one spin. p_lines: 1-20 paylines played, p_bet: points per line (1, 2, 5, 10 or 25).
-- During free spins both are ignored: the lines and bet that won the free spins are used, and the spin costs nothing.
create or replace function public.slot_spin(p_server uuid, p_lines int, p_bet int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  -- 0 apple, 1 beans, 2 bandage, 3 battery, 4 axe, 5 morphine, 6 plate carrier, 7 scoped rifle, 8 WILD (gas), 9 SCATTER (heli)
  w int[] := array[22, 20, 18, 14, 11, 8, 6, 4, 3, 3];
  -- line pays, times the line bet, for 3 / 4 / 5 in a row from the left (row = symbol + 1)
  pay int[] := array[[12, 25, 70], [12, 30, 90], [16, 40, 120], [22, 60, 180], [25, 80, 280],
                     [40, 140, 450], [60, 230, 900], [100, 450, 2000], [150, 900, 5000]];
  -- row (0 top, 1 middle, 2 bottom) on each of the 5 reels
  lines int[] := array[[1,1,1,1,1],[0,0,0,0,0],[2,2,2,2,2],[0,1,2,1,0],[2,1,0,1,2],[0,0,1,2,2],[2,2,1,0,0],[1,0,0,0,1],[1,2,2,2,1],[0,1,1,1,0],
                       [2,1,1,1,2],[1,0,1,0,1],[1,2,1,2,1],[0,1,0,1,0],[2,1,2,1,2],[1,1,0,1,1],[1,1,2,1,1],[0,0,1,0,0],[2,2,1,2,2],[0,2,0,2,0]];
  scat_pay int[] := array[4, 20, 100];   -- 3 / 4 / 5+ heli crashes anywhere, times the total bet
  scat_free int[] := array[6, 10, 15];   -- free spins they give
  g game_players; total int := 0; r int; i int; c int; li int; grid int[] := '{}'; seq int[];
  wr int; n int; sym int; best int; bsym int; bn int; nl int; nb int; cost int; win bigint := 0; is_free boolean;
  wins jsonb := '[]'; sc int := 0; spay bigint := 0; sfree int := 0;
begin
  if auth.uid() is null then raise exception 'Log in first'; end if;
  if srv_role(p_server) is null then raise exception 'Join the server first'; end if;
  if not coalesce((select games from servers where id = p_server), false) then raise exception 'Games are switched off on this server'; end if;
  g := _merge_player(p_server, auth.uid());
  if g.slot_spins > 0 and g.updated_at > clock_timestamp() - interval '300 milliseconds' then raise exception 'Slow down'; end if;
  is_free := g.slot_free > 0;
  if is_free then nl := g.slot_lines; nb := g.slot_bet; cost := 0;
  else
    if p_lines is null or p_lines not between 1 and 20 then raise exception 'Play 1 to 20 lines'; end if;
    if p_bet is null or p_bet not in (1, 2, 5, 10, 25) then raise exception 'Bet 1, 2, 5, 10 or 25 per line'; end if;
    nl := p_lines; nb := p_bet; cost := nl * nb;
    if g.points < cost then raise exception 'Not enough points: this spin costs %, you have %. Earn more in Loot merge.', cost, g.points; end if;
  end if;

  -- 15 symbols, row by row: grid[row * 5 + reel] with row 0-2 and reel 1-5
  for i in 1 .. array_length(w, 1) loop total := total + w[i]; end loop;
  for i in 1 .. 15 loop
    r := floor(random() * total)::int; sym := 0;
    while r >= w[sym + 1] loop r := r - w[sym + 1]; sym := sym + 1; end loop;
    grid := grid || sym;
    if sym = 9 then sc := sc + 1; end if;
  end loop;

  for li in 1 .. nl loop
    seq := '{}';
    for c in 1 .. 5 loop seq := seq || grid[lines[li][c] * 5 + c]; end loop;
    continue when seq[1] = 9;
    -- a run of wilds pays on its own; otherwise wilds stand in for the first real symbol
    wr := 0; while wr < 5 and seq[wr + 1] = 8 loop wr := wr + 1; end loop;
    best := case when wr >= 3 then pay[9][wr - 2] else 0 end; bsym := 8; bn := wr;
    sym := null; for c in 1 .. 5 loop if seq[c] <> 8 then sym := seq[c]; exit; end if; end loop;
    if sym is not null and sym <> 9 then
      n := 0; while n < 5 and (seq[n + 1] = sym or seq[n + 1] = 8) loop n := n + 1; end loop;
      if n >= 3 and pay[sym + 1][n - 2] > best then best := pay[sym + 1][n - 2]; bsym := sym; bn := n; end if;
    end if;
    if best > 0 then
      wins := wins || jsonb_build_array(jsonb_build_object('l', li - 1, 's', bsym, 'n', bn, 'p', best * nb));
      win := win + best * nb;
    end if;
  end loop;
  if sc >= 3 then
    spay := scat_pay[least(sc, 5) - 2] * nl * nb; sfree := scat_free[least(sc, 5) - 2];
    win := win + spay;
  end if;

  update game_players set points = points - cost + win,
    slot_free = slot_free - case when is_free then 1 else 0 end + sfree,
    slot_lines = case when is_free then slot_lines else nl end, slot_bet = case when is_free then slot_bet else nb end,
    slot_spins = slot_spins + 1, slot_won = slot_won + win, slot_best = greatest(slot_best, win), updated_at = clock_timestamp()
    where server_id = p_server and user_id = auth.uid() returning * into g;
  if win >= nl * nb * 100 then
    insert into game_log (server_id, user_id, kind, game, amount, balance) values (p_server, auth.uid(), 'jackpot', 'slots', win, g.points);
  elsif win >= nl * nb * 25 then
    insert into game_log (server_id, user_id, kind, game, amount, balance) values (p_server, auth.uid(), 'big_win', 'slots', win, g.points);
  end if;
  return jsonb_build_object('grid', to_jsonb(grid), 'wins', wins, 'scatter', jsonb_build_object('n', sc, 'pay', spay, 'free', sfree),
    'win', win, 'cost', cost, 'free', is_free, 'free_left', g.slot_free, 'lines', nl, 'bet', nb, 'points', g.points);
end $$;
grant execute on function public.slot_spin(uuid, int, int) to authenticated;
revoke execute on function public.slot_spin(uuid, int, int) from public, anon;

-- the leaderboard API also reports slots
create or replace function public.api_scores(p_key text, p_limit int default 50) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k api_keys; s servers;
begin
  k := _api_key(p_key);
  select * into s from servers where id = k.server_id;
  return jsonb_build_object(
    'server', jsonb_build_object('id', s.id, 'name', s.name),
    'players', coalesce((select jsonb_agg(row_to_json(t)) from (
      select p.username, fa.tag as faction_tag, fa.name as faction, w.merges as upgrades, w.points, w.helis, w.best_item,
        w.slot_spins, w.slot_best, w.updated_at
      from game_players w join profiles p on p.id = w.user_id
      left join faction_members fm on fm.server_id = w.server_id and fm.user_id = w.user_id
      left join factions fa on fa.id = fm.faction_id
      where w.server_id = k.server_id
      order by w.merges desc, w.points desc, w.updated_at
      limit greatest(1, least(coalesce(p_limit, 50), 500))) t), '[]'));
end $$;
grant execute on function public.api_scores(text, int) to anon, authenticated;

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
