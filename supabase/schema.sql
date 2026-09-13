-- ════════════════════════════════════════════════════════════════════════════
-- Waypoints — Supabase schema
-- ════════════════════════════════════════════════════════════════════════════
-- Run this once in your project's SQL Editor (app.supabase.com → SQL Editor →
-- New query → paste → Run). It is safe to re-run: every statement is guarded.
--
-- What it sets up:
--   profiles       one row per account, holding the username people add you by
--   trips          the trips themselves, owned by whoever created them
--   trip_members   who can see and edit each trip
--   journal_entries  entries, attributed to whoever wrote them
--
-- Everything is locked down with row-level security, so a signed-in person can
-- only ever touch trips they are a member of.
-- ════════════════════════════════════════════════════════════════════════════


-- ── TABLES ──────────────────────────────────────────────────────────────────

create table if not exists profiles (
  id uuid primary key references auth.users on delete cascade,
  username text unique,
  created_at timestamptz not null default now(),
  constraint profiles_username_format
    check (username is null or username ~ '^[a-z0-9_]{3,20}$')
);

create table if not exists trips (
  id text primary key,
  user_id uuid references auth.users not null default auth.uid(),  -- the owner
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

-- If you created these tables before the planner or sharing existed:
alter table trips add column if not exists plan jsonb default '{}';

create table if not exists trip_members (
  trip_id text references trips(id) on delete cascade not null,
  user_id uuid references auth.users on delete cascade not null,
  role text not null default 'companion' check (role in ('owner','companion')),
  added_at timestamptz not null default now(),
  primary key (trip_id, user_id)
);

create table if not exists journal_entries (
  id uuid primary key default gen_random_uuid(),
  trip_id text references trips(id) on delete cascade not null,
  user_id uuid references auth.users not null default auth.uid(),
  title text,
  body text not null,
  created_at date not null default current_date
);

create index if not exists journal_entries_trip_id_idx on journal_entries(trip_id);
create index if not exists trip_members_user_id_idx on trip_members(user_id);


-- ── HELPERS ─────────────────────────────────────────────────────────────────
-- These are SECURITY DEFINER on purpose. A policy on `trips` that asks
-- "is this person a member?" has to read `trip_members`, and a policy on
-- `trip_members` has to read `trips` — written directly against the tables that
-- recurses forever and Postgres aborts the query. Reading through a definer
-- function skips RLS on the inner read and breaks the cycle.

create or replace function public.is_trip_member(p_trip_id text)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from trip_members
    where trip_id = p_trip_id and user_id = auth.uid()
  );
$$;

create or replace function public.is_trip_owner(p_trip_id text)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from trips
    where id = p_trip_id and user_id = auth.uid()
  );
$$;


-- ── ROW-LEVEL SECURITY ──────────────────────────────────────────────────────

alter table profiles        enable row level security;
alter table trips           enable row level security;
alter table trip_members    enable row level security;
alter table journal_entries enable row level security;

-- profiles: you can read and edit your own. Usernames are never listed in bulk —
-- looking someone up goes through add_trip_member() below, so nobody can scrape
-- the table for who else uses the app.
drop policy if exists "Read your own profile" on profiles;
create policy "Read your own profile" on profiles
  for select using (id = auth.uid());

drop policy if exists "Create your own profile" on profiles;
create policy "Create your own profile" on profiles
  for insert with check (id = auth.uid());

drop policy if exists "Update your own profile" on profiles;
create policy "Update your own profile" on profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- trips: members see and edit; only the owner can delete.
-- The insert policy also allows members, because the app saves with upsert and
-- Postgres checks INSERT's WITH CHECK even when the row already exists.
drop policy if exists "Members read trips" on trips;
create policy "Members read trips" on trips
  for select using (user_id = auth.uid() or public.is_trip_member(id));

drop policy if exists "Create or upsert a trip you belong to" on trips;
create policy "Create or upsert a trip you belong to" on trips
  for insert with check (user_id = auth.uid() or public.is_trip_member(id));

drop policy if exists "Members update trips" on trips;
create policy "Members update trips" on trips
  for update using (user_id = auth.uid() or public.is_trip_member(id))
           with check (user_id = auth.uid() or public.is_trip_member(id));

drop policy if exists "Owner deletes trips" on trips;
create policy "Owner deletes trips" on trips
  for delete using (user_id = auth.uid());

-- trip_members: members see the roster; only the owner changes it (though
-- anyone can remove themselves, i.e. leave a trip).
drop policy if exists "Members see the roster" on trip_members;
create policy "Members see the roster" on trip_members
  for select using (public.is_trip_member(trip_id));

drop policy if exists "Owner adds travellers" on trip_members;
create policy "Owner adds travellers" on trip_members
  for insert with check (public.is_trip_owner(trip_id));

drop policy if exists "Owner removes travellers or you leave" on trip_members;
create policy "Owner removes travellers or you leave" on trip_members
  for delete using (public.is_trip_owner(trip_id) or user_id = auth.uid());

-- journal_entries: any member reads and writes; you only edit your own words.
drop policy if exists "Members read the journal" on journal_entries;
create policy "Members read the journal" on journal_entries
  for select using (public.is_trip_member(trip_id));

drop policy if exists "Members write the journal" on journal_entries;
create policy "Members write the journal" on journal_entries
  for insert with check (public.is_trip_member(trip_id) and user_id = auth.uid());

drop policy if exists "Edit your own entries" on journal_entries;
create policy "Edit your own entries" on journal_entries
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Delete your own entries" on journal_entries;
create policy "Delete your own entries" on journal_entries
  for delete using (user_id = auth.uid());


-- ── DATA API PERMISSIONS ────────────────────────────────────────────────────
-- Supabase has a project setting, "Automatically expose new tables", that
-- decides whether tables get privileges for the API roles by default. Granting
-- explicitly here means this schema works whichever way that switch is set,
-- rather than silently returning "permission denied" on every query.
--
-- These grants only decide who may attempt a query. The row-level security
-- above is what decides which rows come back — and `anon` is deliberately given
-- nothing, because every policy here requires a signed-in auth.uid().

grant usage on schema public to anon, authenticated;

grant select, insert, update, delete
  on table profiles, trips, trip_members, journal_entries
  to authenticated;

grant execute on function
  public.is_trip_member(text),
  public.is_trip_owner(text)
  to authenticated;

-- Supabase's "Automatically expose new tables" setting grants anon by default,
-- which would quietly undo the line above. Take it back explicitly: every policy
-- in this schema requires a signed-in auth.uid(), so an unauthenticated role has
-- no business reaching these tables at all. RLS would return zero rows anyway —
-- this is the second lock, for the day someone disables RLS on a table by hand.
revoke all on table profiles, trips, trip_members, journal_entries from anon;


-- ── TRIGGERS ────────────────────────────────────────────────────────────────

-- Every new account gets an empty profile row; the app prompts for a username.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Whoever creates a trip is immediately a member of it, as owner.
create or replace function public.add_owner_as_member()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.trip_members (trip_id, user_id, role)
  values (new.id, new.user_id, 'owner')
  on conflict do nothing;
  return new;
end $$;

drop trigger if exists trips_owner_is_member on trips;
create trigger trips_owner_is_member
  after insert on trips
  for each row execute function public.add_owner_as_member();

-- Backfill, in case you already had trips before sharing existed.
insert into trip_members (trip_id, user_id, role)
select id, user_id, 'owner' from trips
on conflict do nothing;


-- ── RPCs THE APP CALLS ──────────────────────────────────────────────────────
-- Each returns {ok:true, …} or {ok:false, error:'…'} so the app can show the
-- reason rather than a raw Postgres error.

create or replace function public.my_profile()
returns json language sql security definer stable set search_path = public as $$
  select json_build_object(
    'id', auth.uid(),
    'username', (select username from profiles where id = auth.uid())
  );
$$;

create or replace function public.set_username(p_username text)
returns json language plpgsql security definer set search_path = public as $$
declare v_clean text;
begin
  if auth.uid() is null then
    return json_build_object('ok', false, 'error', 'You are not signed in.');
  end if;
  v_clean := lower(trim(p_username));
  if v_clean !~ '^[a-z0-9_]{3,20}$' then
    return json_build_object('ok', false, 'error',
      'Usernames are 3–20 characters: letters, numbers and underscores.');
  end if;
  if exists (select 1 from profiles where username = v_clean and id <> auth.uid()) then
    return json_build_object('ok', false, 'error', 'That username is already taken.');
  end if;
  insert into profiles (id, username) values (auth.uid(), v_clean)
    on conflict (id) do update set username = excluded.username;
  return json_build_object('ok', true, 'username', v_clean);
end $$;

-- Accepts either a username or an email address. Email matters because the
-- person you want to add has usually signed in already but not bothered with a
-- username, and you know their email — insisting on a username first is a
-- coordination problem the app invented for itself.
drop function if exists public.add_trip_member(text, text);
create or replace function public.add_trip_member(p_trip_id text, p_identifier text)
returns json language plpgsql security definer set search_path = public as $$
declare v_uid uuid; v_clean text;
begin
  if not public.is_trip_owner(p_trip_id) then
    return json_build_object('ok', false, 'error',
      'Only the person who created the trip can add travellers.');
  end if;
  v_clean := lower(trim(p_identifier));
  if v_clean = '' then
    return json_build_object('ok', false, 'error', 'Type a username or email first.');
  end if;

  if position('@' in v_clean) > 0 then
    select id into v_uid from auth.users where lower(email) = v_clean;
    if v_uid is null then
      return json_build_object('ok', false, 'error',
        'Nobody has signed in with that email yet. They need to open the app and sign in once first.');
    end if;
  else
    select id into v_uid from profiles where username = v_clean;
    if v_uid is null then
      return json_build_object('ok', false, 'error',
        'No one is using that username. Try their email instead.');
    end if;
  end if;

  if v_uid = auth.uid() then
    return json_build_object('ok', false, 'error', 'That is you — you are already on this trip.');
  end if;

  insert into trip_members (trip_id, user_id, role)
  values (p_trip_id, v_uid, 'companion')
  on conflict do nothing;

  return json_build_object('ok', true, 'who',
    coalesce((select '@' || username from profiles where id = v_uid), v_clean));
end $$;

create or replace function public.trip_roster(p_trip_id text)
returns table (user_id uuid, username text, role text, is_you boolean)
language sql security definer stable set search_path = public as $$
  select m.user_id, p.username, m.role, (m.user_id = auth.uid())
  from trip_members m
  left join profiles p on p.id = m.user_id
  where m.trip_id = p_trip_id and public.is_trip_member(p_trip_id)
  order by (m.role = 'owner') desc, p.username nulls last;
$$;

create or replace function public.remove_trip_member(p_trip_id text, p_user_id uuid)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_trip_owner(p_trip_id) or p_user_id = auth.uid()) then
    return json_build_object('ok', false, 'error',
      'Only the trip owner can remove someone else.');
  end if;
  if exists (select 1 from trip_members
             where trip_id = p_trip_id and user_id = p_user_id and role = 'owner') then
    return json_build_object('ok', false, 'error',
      'The trip owner cannot be removed. Delete the trip instead.');
  end if;
  delete from trip_members where trip_id = p_trip_id and user_id = p_user_id;
  return json_build_object('ok', true);
end $$;

create or replace function public.trip_journal(p_trip_id text)
returns table (id uuid, title text, body text, created_at date, author text, is_you boolean)
language sql security definer stable set search_path = public as $$
  select j.id, j.title, j.body, j.created_at, p.username, (j.user_id = auth.uid())
  from journal_entries j
  left join profiles p on p.id = j.user_id
  where j.trip_id = p_trip_id and public.is_trip_member(p_trip_id)
  order by j.created_at desc, j.id desc;
$$;


grant execute on function
  public.my_profile(),
  public.set_username(text),
  public.add_trip_member(text, text),
  public.trip_roster(text),
  public.remove_trip_member(text, uuid),
  public.trip_journal(text)
  to authenticated;
