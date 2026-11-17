# Tunnel Rats Map

Shared DayZ faction map: accounts, servers, factions, markers, compounds, notes, road GPS and an API.
Map tiles come from iZurvive; all player data lives in Supabase.

## How it runs
- **Website:** static files in this folder, hosted on GitHub Pages at https://alonestatistic.github.io/tunnel-rats-map/. Every push to `main` deploys automatically (about a minute).
- **Data:** Supabase (accounts, servers, factions, markers, notes, API keys). Settings are in `config.js`.

## Files
| File | What it is |
| --- | --- |
| `index.html` | The whole app |
| `api.html` | API docs for bots and other apps |
| `config.js` | Title, Supabase URL/key, default map |
| `maps.js`, `mapdata/` | All iZurvive maps and their towns / loot layers |
| `refdata.js`, `roads.js` | Nasdara towns, layers and road network (GPS) |
| `flags.js` | Armband flags and their preset colours |
| `db/supabase-v2.sql` | Database schema (already run). Kept for reference / new setups |
| `db/supabase-setup.sql` | The old v1 table, still read by "Import from old version" |

## Run locally
```
python -m http.server 8123
```
then open http://localhost:8123.
