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

## Accounts and sharing a trip

Without Supabase, trips live in one browser and only you see them. Connect it and you get accounts, syncing, and trips shared with the people you're actually travelling with.

**How sharing works.** Everyone picks a **username** the first time they sign in. To share a trip, its owner types the other person's username — no emails exchanged, nothing to accept. From then on both of you see the same trip, edit the same bookings, and write into the same journal, with each entry showing who wrote it. Only the owner can add or remove travellers; companions can edit everything else and can remove themselves.

### 1. Create the Supabase project

1. [supabase.com](https://supabase.com) → **New project**. The free tier is plenty. Save the database password somewhere.
2. **SQL Editor → New query** → paste all of [supabase/schema.sql](supabase/schema.sql) → **Run**. This creates `profiles`, `trips`, `trip_members` and `journal_entries`, locks them down with row-level security, and adds the functions the app calls. It's safe to re-run.
3. **Authentication → Providers** → make sure **Email** is on. Sign-in is a passwordless magic link.
4. **Authentication → URL Configuration** → set **Site URL** to wherever the app is served, and add every other address you'll open it from to **Redirect URLs**. If you skip this, the magic link will bounce you to the wrong place or refuse outright. Add all of these that apply:
   - your live URL, e.g. `https://<username>.github.io/waypoints/app/waypoints.html`
   - `http://localhost:8991/app/waypoints.html` if you also run it locally
5. **Settings → API** → copy the **Project URL** and the **anon public** key. Not the `service_role` key — that one bypasses row-level security and must never appear in client code.

### 2. Point the app at it

*Already done for this repo — it's wired to the `Waypoints` project (`pmglrywhasraqrnnudhy`). The rest of this section is for anyone setting up their own copy.*

In `app/waypoints.html`, near the top of the `<script>` block:

```js
var SUPABASE_URL = 'YOUR_SUPABASE_URL';
var SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```

Replace both. The app detects a real URL and switches itself on.

*(The publishable/anon key is designed to be public and is fine in a public repo — Supabase's security model rests on the row-level security policies in the schema, not on hiding this key. The `secret`/`service_role` key is the opposite: it bypasses RLS entirely and must never appear in client code.)*

### 3. Get everyone on the trip

1. **You:** open the app, **My Trips**, enter your email, click the magic link, pick your username.
2. Open it **from the copy of the app that has your `my-trips.local.js`** — signing in there pushes those trips up to your account. After that they're in the database and reachable from anywhere.
3. **Them:** open the app, sign in with their own email, pick their own username, tell you what it is.
4. **You:** open the trip → **Overview** → **Travelling together** → type their username → **Add traveller**. It shows up for them immediately.

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
