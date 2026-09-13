# Waypoints

Two halves in one static HTML file — [app/waypoints.html](app/waypoints.html):

- **Explore** — a destination recommender. 87 destinations, filters, a world map, seasonal budget estimates.
- **My Trips** — a planner and logbook for trips you're actually taking. Day-by-day itinerary, a bookings checklist you tick off, flights and ground transfers, planned-vs-actual costs, and a journal.

Both work with **zero setup**. Trips are saved in your browser by default; connecting Supabase is optional and only adds syncing across devices.

## Your own trips

Real trips live in `app/my-trips.local.js`, which is git-ignored. That's deliberate: it holds PNRs, booking references and prices, and a GitHub Pages site is publicly viewable even when the repo behind it is private. The app loads the file if it's there and works fine if it isn't.

The file exports one array:

```js
var SEED_TRIPS = [{
  id: 'bali-singapore-2026',
  name: 'Bali & Singapore',
  emoji: '🌴',
  countries: ['id', 'sg'],        // ISO-3166 alpha-2, used to light up the map
  start: '2026-09-16',
  end: '2026-09-30',
  status: 'upcoming',             // 'upcoming' | 'completed'
  travellers: 2,
  summary: '…',
  highlights: ['…'],
  alerts:    [{ level, title, body }],          // unresolved questions, shown up top
  legs:      [{ id, emoji, name, place, start, end, nights, stay, stayStatus, price, url, note }],
  itinerary: [{ date, legId, emoji, title, items: ['…'] }],
  bookings:  [{ id, cat, status, title, detail, price, url }],  // status: 'done' | 'todo' | 'hold'
  transfers: [{ route, time, cost }],
  flights:   [{ code, date, from, to, dep, arr, pnr }],
  todos:     [{ done, text }],
  costs:     { flights: { planned, actual, note }, … }
}];
```

`cat` on a booking, and the keys of `costs`, both come from the same set: `flights`, `accommodation`, `transport`, `activities`, `food`, `other`.

A trip is imported the **first time** the app sees its `id`. After that your edits in the app own it — ticking a booking off or checking an open item is saved immediately, and re-loading the page never overwrites those. If you edit the file and want the app to take the new version, run `waypointsResyncSeeds()` in the browser console; that replaces the stored copy and discards whatever you'd ticked off on those trips.

You can also add trips through the UI (**+ Log a trip**) — those get the logbook fields, and you can fill in the planner fields by editing the file or the database.

## Syncing across devices (optional)

Everything above works without any of this. Connect Supabase only if you want the same trips on your phone and your laptop.

### 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com) → **New project**. Free tier is plenty.
2. Once it's created, open **SQL Editor** → **New query**, paste in the contents of [supabase/schema.sql](supabase/schema.sql), and run it. This creates the `trips` and `journal_entries` tables with row-level security, so each signed-in user only ever sees their own rows.
3. Go to **Authentication → Providers** and make sure **Email** is enabled (it is by default). The app signs people in with a passwordless magic link — no separate password to manage.
4. Go to **Settings → API**. You need two values from this page:
   - **Project URL**
   - **anon public** key (not the `service_role` key — that one must never go in client-side code)

### 2. Connect the app to your project

Open `app/waypoints.html`, find this near the top of the `<script>` block:

```js
var SUPABASE_URL = 'YOUR_SUPABASE_URL';
var SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```

Replace both placeholders with the values from the previous step. That's it — the app detects a real URL automatically and switches from "not configured" to fully live.

*(The anon key is meant to be public — Supabase's security model relies on the row-level security policies from the schema, not on hiding this key. Never put the `service_role` key here.)*

## Run it locally

It's a single static file — open `app/waypoints.html` directly in a browser, or serve the folder with anything static:

```bash
python3 -m http.server 8080
```

## Deploy it live (GitHub Pages)

1. Push this repo to GitHub (private is fine — Pages sites are publicly viewable regardless of repo visibility, but the source history/issues/etc. stay private).
2. Repo → **Settings → Pages** → **Source: Deploy from a branch** → pick `main` and `/ (root)`.
3. Your live URL will be `https://<your-username>.github.io/<repo-name>/app/waypoints.html`.

## Project structure

```
app/waypoints.html        the whole app — single file, no build step
app/my-trips.local.js     your real trips — git-ignored, optional
supabase/schema.sql       run once in Supabase's SQL editor, only if syncing
```

Personal trip documents (`journal/`, `trips/`) live alongside this project on disk but are intentionally excluded from the repo via `.gitignore` — they're the source material, not part of the app.
