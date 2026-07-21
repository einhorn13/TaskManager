-- Task Manager / Supabase schema. Run in Supabase SQL Editor once.
create extension if not exists pgcrypto;

-- Collaboration tables. The policies and sharing RPC are installed by
-- migrations/202607190001_collaboration.sql (or apply_collaboration_migration.cmd).
create table if not exists public.collaboration_spaces (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), deleted_at timestamptz
);
create table if not exists public.collaboration_members (
  space_id uuid not null references public.collaboration_spaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'editor' check (role in ('owner','editor')),
  accepted_at timestamptz not null default now(), created_at timestamptz not null default now(),
  primary key (space_id, user_id)
);

create or replace function public.set_updated_at()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin new.updated_at = now(); return new; end; $$;

create table if not exists public.folders (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  space_id uuid references public.collaboration_spaces(id) on delete set null,
  name text not null, color text, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), deleted_at timestamptz
);
create table if not exists public.tags (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  name text not null, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), deleted_at timestamptz
);
create table if not exists public.tasks (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  space_id uuid references public.collaboration_spaces(id) on delete set null,
  folder_id uuid references public.folders(id) on delete set null,
  parent_task_id uuid references public.tasks(id) on delete cascade,
  title text not null, description text, due_date timestamptz,
  duration_minutes integer, base_priority smallint not null default 1,
  status text not null default 'todo' check (status in ('todo','done')),
  completed_at timestamptz, position double precision,
  expiring_threshold_days_override integer, recurrence_rule text,
  snooze_count integer not null default 0, is_pinned boolean not null default false,
  tag_ids uuid[] not null default '{}', created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), deleted_at timestamptz
);
create table if not exists public.task_attachments (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  type text not null check (type in ('file','link','photo')), url text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create table if not exists public.checklist_templates (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  title text not null, items jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create table if not exists public.checklists (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  space_id uuid references public.collaboration_spaces(id) on delete set null,
  title text not null, template_id uuid references public.checklist_templates(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create table if not exists public.checklist_items (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  checklist_id uuid not null references public.checklists(id) on delete cascade,
  text text not null, is_done boolean not null default false, position double precision,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

do $$ declare table_name text; begin
  foreach table_name in array array['folders','tags','tasks','task_attachments',
    'checklist_templates','checklists','checklist_items'] loop
    execute format('drop trigger if exists %I_set_updated_at on public.%I', table_name, table_name);
    execute format('create trigger %I_set_updated_at before update on public.%I '
      'for each row execute function public.set_updated_at()', table_name, table_name);
    execute format('alter table public.%I enable row level security', table_name);
    execute format('drop policy if exists own_rows on public.%I', table_name);
    execute format('create policy own_rows on public.%I for all to authenticated '
      'using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', table_name);
  end loop;
end $$;

create index if not exists tasks_user_updated_idx on public.tasks(user_id, updated_at);
create index if not exists tasks_user_due_idx on public.tasks(user_id, due_date);
create index if not exists attachments_user_updated_idx on public.task_attachments(user_id, updated_at);
create index if not exists checklist_items_user_updated_idx on public.checklist_items(user_id, updated_at);

-- Realtime invalidations make shared changes visible to another active client
-- immediately. Periodic pull remains the fallback when Realtime is unavailable.
do $$ declare target text; begin
  foreach target in array array['tasks', 'folders', 'checklists'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = target
    ) then
      execute format('alter publication supabase_realtime add table public.%I', target);
    end if;
  end loop;
end $$;

-- Private bucket for the later upload step. Current clients may still sync local paths;
-- uploading binaries can be enabled without changing the task schema.
insert into storage.buckets(id, name, public)
values ('task-attachments', 'task-attachments', false)
on conflict (id) do nothing;

drop policy if exists own_task_attachments on storage.objects;
create policy own_task_attachments on storage.objects
for all to authenticated
using (bucket_id = 'task-attachments' and (storage.foldername(name))[1] = (select auth.uid())::text)
with check (bucket_id = 'task-attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);
