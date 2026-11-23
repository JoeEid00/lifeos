-- =====================================================================
--  LifeOS – Supabase / PostgreSQL schema
--  Run this whole file once in: Supabase Dashboard → SQL Editor → New query
--  Every table is private per user (Row Level Security).
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- 1) Direction layer: life areas, visions, goals
-- ---------------------------------------------------------------------
create table if not exists public.life_areas (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name        text not null,
  description text,
  icon        text not null default 'growth',
  color       text not null default '#4F46E5',
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

-- Operational categories are SEPARATE from life areas (task / habit / idea / shopping)
create table if not exists public.categories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind        text not null check (kind in ('task','habit','idea','shopping')),
  name        text not null,
  color       text not null default '#64748B',
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists public.visions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title       text not null,
  description text,
  area_id     uuid references public.life_areas(id) on delete set null,
  created_at  timestamptz not null default now()
);

create table if not exists public.goals (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users(id) on delete cascade,
  vision_id       uuid references public.visions(id) on delete set null,
  area_id         uuid references public.life_areas(id) on delete set null,
  title           text not null,
  description     text,
  target_date     date,
  status          text not null default 'active' check (status in ('active','achieved','paused','dropped')),
  manual_progress int  not null default 0 check (manual_progress between 0 and 100),
  created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 2) Planning layer: projects (+ sub-projects), milestones, notes, tasks
-- ---------------------------------------------------------------------
create table if not exists public.projects (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  goal_id     uuid references public.goals(id) on delete set null,
  area_id     uuid references public.life_areas(id) on delete set null,
  parent_id   uuid references public.projects(id) on delete set null,
  name        text not null,
  description text,
  status      text not null default 'active' check (status in ('planning','active','on_hold','done','archived')),
  due_date    date,
  color       text not null default '#4F46E5',
  created_at  timestamptz not null default now()
);

create table if not exists public.milestones (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  project_id  uuid not null references public.projects(id) on delete cascade,
  title       text not null,
  description text,
  due_date    date,
  sort_order  int  not null default 0,
  done        boolean not null default false,
  created_at  timestamptz not null default now()
);

create table if not exists public.project_notes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  project_id  uuid not null references public.projects(id) on delete cascade,
  content     text not null,
  created_at  timestamptz not null default now()
);

create table if not exists public.tasks (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title            text not null,
  notes            text,
  due_date         date,
  priority         int  not null default 0 check (priority between 0 and 3),
  status           text not null default 'todo' check (status in ('todo','doing','done')),
  completed_at     timestamptz,
  project_id       uuid references public.projects(id)   on delete set null,
  milestone_id     uuid references public.milestones(id) on delete set null,
  goal_id          uuid references public.goals(id)      on delete set null,
  category_id      uuid references public.categories(id) on delete set null,
  steps            jsonb  not null default '[]'::jsonb,   -- [{title, done}]
  links            text[] not null default '{}',          -- image / video / resource URLs
  estimate_minutes int,
  created_at       timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3) Execution layer: habits (+ routine steps), habit logs, planner
-- ---------------------------------------------------------------------
create table if not exists public.habits (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title            text not null,
  description      text,
  frequency        text not null default 'daily' check (frequency in ('daily','weekly','monthly')),
  target           int  not null default 1 check (target >= 1),
  preferred_time   text,                                  -- 'HH:mm'
  duration_minutes int  not null default 30,
  area_id          uuid references public.life_areas(id) on delete set null,
  category_id      uuid references public.categories(id) on delete set null,
  color            text not null default '#10B981',
  steps            jsonb not null default '[]'::jsonb,    -- nested routine steps [{title}]
  archived         boolean not null default false,
  sort_order       int not null default 0,
  created_at       timestamptz not null default now()
);

create table if not exists public.habit_logs (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  habit_id    uuid not null references public.habits(id) on delete cascade,
  date        date not null,
  note        text,
  created_at  timestamptz not null default now(),
  unique (habit_id, date)
);

-- A plan item is the *schedule* (when you will do it). Editing it never
-- changes the task due date or the habit's default time.
create table if not exists public.plan_items (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references auth.users(id) on delete cascade,
  date             date not null,
  start_time       text not null default '09:00',
  duration_minutes int  not null default 30 check (duration_minutes > 0),
  task_id          uuid references public.tasks(id)  on delete cascade,
  habit_id         uuid references public.habits(id) on delete cascade,
  title            text,
  notes            text,                                  -- notes for the schedule block itself
  done             boolean not null default false,
  skipped          boolean not null default false,        -- hides a recurring habit on that day
  created_at       timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 4) Capture layer: ideas, wisdom, shopping, time, journal
-- ---------------------------------------------------------------------
create table if not exists public.idea_stages (           -- synced across devices
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name        text not null,
  color       text not null default '#64748B',
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists public.ideas (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null default auth.uid() references auth.users(id) on delete cascade,
  stage_id             uuid references public.idea_stages(id) on delete set null,
  category_id          uuid references public.categories(id)  on delete set null,
  title                text not null,
  content              text,                                -- original text, never overwritten by updates
  updates              jsonb not null default '[]'::jsonb,  -- [{date, text}]
  converted_task_id    uuid references public.tasks(id)    on delete set null,
  converted_project_id uuid references public.projects(id) on delete set null,
  created_at           timestamptz not null default now()
);

create table if not exists public.wisdom_entries (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title       text,
  content     text not null check (char_length(content) <= 5000),
  category    text not null default 'mindset',
  tags        text[] not null default '{}',
  collection  text,
  favorite    boolean not null default false,
  created_at  timestamptz not null default now()
);

create table if not exists public.shopping_items (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name            text not null,
  category_id     uuid references public.categories(id) on delete set null,
  quantity        numeric not null default 1,
  estimated_price numeric,                -- per unit
  actual_paid     numeric,                -- total actually paid
  purchased       boolean not null default false,
  purchased_at    date,                   -- real purchase date
  target_date     date,
  notes           text,
  created_at      timestamptz not null default now()
);

create table if not exists public.time_entries (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  description text,
  started_at  timestamptz not null,
  ended_at    timestamptz,                -- null = timer still running
  task_id     uuid references public.tasks(id)      on delete set null,
  project_id  uuid references public.projects(id)   on delete set null,
  area_id     uuid references public.life_areas(id) on delete set null,
  created_at  timestamptz not null default now()
);

create table if not exists public.journal_entries (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  date        date not null default current_date,
  content     text not null default '',
  mood        int check (mood between 1 and 5),   -- null = not recorded
  tags        text[] not null default '{}',
  created_at  timestamptz not null default now(),
  unique (user_id, date)
);

-- ---------------------------------------------------------------------
-- 5) Analysis layer: weekly reviews
-- ---------------------------------------------------------------------
create table if not exists public.weekly_reviews (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users(id) on delete cascade,
  week_start      date not null,
  wins            text,
  challenges      text,
  lessons         text,
  next_priorities text,
  rating          int check (rating between 1 and 10),
  created_at      timestamptz not null default now(),
  unique (user_id, week_start)
);

-- ---------------------------------------------------------------------
-- Row Level Security + indexes for every table
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'life_areas','categories','visions','goals','projects','milestones','project_notes',
    'tasks','habits','habit_logs','plan_items','idea_stages','ideas','wisdom_entries',
    'shopping_items','time_entries','journal_entries','weekly_reviews'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "owner_all" on public.%I', t);
    execute format(
      'create policy "owner_all" on public.%I for all to authenticated
         using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
    execute format('create index if not exists %I on public.%I (user_id)', t || '_user_idx', t);
  end loop;
end $$;

create index if not exists tasks_project_idx      on public.tasks (project_id);
create index if not exists tasks_due_idx          on public.tasks (user_id, due_date);
create index if not exists habit_logs_habit_idx   on public.habit_logs (habit_id, date);
create index if not exists plan_items_date_idx    on public.plan_items (user_id, date);
create index if not exists time_entries_start_idx on public.time_entries (user_id, started_at);
