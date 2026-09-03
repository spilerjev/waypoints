# Waypoints

A travel planner (87 destinations, filters, a world map, budget estimates) and a private trip logbook (your own trips, costs, and journal), in one static HTML file — [app/waypoints.html](app/waypoints.html).

**Explore** works with zero setup. **My Trips** needs a Supabase project connected — that's the only backend this app has, and it's what makes trip data private to you instead of baked into the page's source.

## 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com) → **New project**. Free tier is plenty.
2. Once it's created, open **SQL Editor** → **New query**, paste in the contents of [supabase/schema.sql](supabase/schema.sql), and run it. This creates the `trips` and `journal_entries` tables with row-level security, so each signed-in user only ever sees their own rows.
3. Go to **Authentication → Providers** and make sure **Email** is enabled (it is by default). The app signs people in with a passwordless magic link — no separate password to manage.
4. Go to **Settings → API**. You need two values from this page:
   - **Project URL**
   - **anon public** key (not the `service_role` key — that one must never go in client-side code)

## 2. Connect the app to your project

Open `app/waypoints.html`, find this near the top of the `<script>` block:

```js
var SUPABASE_URL = 'YOUR_SUPABASE_URL';
var SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```

Replace both placeholders with the values from step 1.4. That's it — the app detects a real URL automatically and switches from "not configured" to fully live.

*(The anon key is meant to be public — Supabase's security model relies on the row-level security policies from the schema, not on hiding this key. Never put the `service_role` key here.)*

## 3. Run it locally

It's a single static file — open `app/waypoints.html` directly in a browser, or serve the folder with anything static:

```bash
python3 -m http.server 8080
```

## 4. Deploy it live (GitHub Pages)

1. Push this repo to GitHub (private is fine — Pages sites are publicly viewable regardless of repo visibility, but the source history/issues/etc. stay private).
2. Repo → **Settings → Pages** → **Source: Deploy from a branch** → pick `main` and `/ (root)`.
3. Your live URL will be `https://<your-username>.github.io/<repo-name>/app/waypoints.html`.

## Project structure

```
app/waypoints.html        the whole app — single file, no build step
supabase/schema.sql        run once in Supabase's SQL editor
```

Personal trip documents (`journal/`, `trips/`) live alongside this project on disk but are intentionally excluded from the repo via `.gitignore` — they're not part of the app.
