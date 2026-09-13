-- Waypoints — Supabase schema
-- Run this once in your Supabase project's SQL Editor (https://app.supabase.com → your project → SQL Editor → New query).
-- It creates the two tables the app needs and locks them down so each signed-in user can only ever see their own rows.

create table if not exists trips (
  id text primary key,
  user_id uuid references auth.users not null default auth.uid(),
  name text not null,
  emoji text,
  countries text[] default '{}',
  start_date date not null,
  end_date date not null,
  status text not null default 'upcoming',
  summary text,
  highlights jsonb default '[]',
  costs jsonb default '{}',
  -- Everything the planner adds on top of the logbook: legs, itinerary,
  -- bookings, transfers, todos, alerts, flights, travellers. One jsonb blob so
  -- the plan can grow without a migration every time.
  plan jsonb default '{}',
  created_at timestamptz not null default now()
);

-- If you created this table before the planner existed, this adds the column.
alter table trips add column if not exists plan jsonb default '{}';

alter table trips enable row level security;

create policy "Users manage their own trips"
  on trips
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists journal_entries (
  id uuid primary key default gen_random_uuid(),
  trip_id text references trips(id) on delete cascade not null,
  user_id uuid references auth.users not null default auth.uid(),
  title text,
  body text not null,
  created_at date not null default current_date
);

alter table journal_entries enable row level security;

create policy "Users manage their own journal entries"
  on journal_entries
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists journal_entries_trip_id_idx on journal_entries(trip_id);
