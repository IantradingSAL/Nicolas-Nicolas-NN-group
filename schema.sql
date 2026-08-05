-- Nicolas Nicolas Group — Supabase schema
--
-- Run this in the Supabase SQL editor (Project → SQL → New query)
-- after you plug your real URL + anon key into config.js.
--
-- The tables mirror the ones the HTML pages call into:
--   suppliers, supplier_documents, inventory_items,
--   employees, role_templates, time_sessions, user_views, audit_log
--
-- RLS is enabled everywhere but the policies are permissive
-- (authenticated users can read/write). Tighten them for
-- production — this is a starter for a fresh, empty deployment.

-- ─── extensions ──────────────────────────────────────────────────
create extension if not exists "pgcrypto";

-- ─── suppliers ───────────────────────────────────────────────────
create table if not exists public.suppliers (
  id                        uuid primary key default gen_random_uuid(),
  name                      text not null,
  country                   text,
  contact_name              text,
  phone                     text,
  email                     text,
  cc_emails                 text,
  address                   text,
  notes                     text,
  default_price_per_aligner numeric,
  default_currency          text default 'EUR',
  is_default_distributor    boolean default false,
  is_active                 boolean default true,
  created_at                timestamptz not null default now()
);

create table if not exists public.supplier_documents (
  id             uuid primary key default gen_random_uuid(),
  supplier_id    uuid not null references public.suppliers(id) on delete cascade,
  kind           text not null default 'certification',
  title          text,
  reference_no   text,
  expires_at     date,
  attachment_url text,
  created_at     timestamptz not null default now()
);

-- ─── inventory ───────────────────────────────────────────────────
create table if not exists public.inventory_items (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null,
  sku                   text unique,
  quantity              numeric default 0,
  unit                  text default 'pcs',
  reorder_level         numeric,
  preferred_supplier_id uuid references public.suppliers(id) on delete set null,
  notes                 text,
  created_at            timestamptz not null default now()
);

-- ─── roles / employees ───────────────────────────────────────────
create table if not exists public.role_templates (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  description text,
  permissions jsonb default '{}'::jsonb,
  is_system   boolean default false,
  created_at  timestamptz not null default now()
);

create table if not exists public.employees (
  id           uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  full_name    text not null,
  email        text,
  phone        text,
  role_id      uuid references public.role_templates(id) on delete set null,
  extra_roles  uuid[],
  is_active    boolean default true,
  hired_at     date,
  created_at   timestamptz not null default now()
);

create table if not exists public.time_sessions (
  id           uuid primary key default gen_random_uuid(),
  employee_id  uuid not null references public.employees(id) on delete cascade,
  started_at   timestamptz not null default now(),
  ended_at     timestamptz,
  notes        text
);

-- ─── saved filter views (per-user chip row) ──────────────────────
create table if not exists public.user_views (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null default auth.uid() references auth.users(id) on delete cascade,
  page       text not null,
  name       text not null,
  filters    jsonb not null default '{}'::jsonb,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists user_views_owner_page_idx on public.user_views(owner_id, page);

-- ─── audit_log — every-user, every-action trace ──────────────────
create table if not exists public.audit_log (
  id         uuid primary key,
  session_id uuid,
  user_id    uuid,
  user_email text,
  page       text,
  action     text not null,
  target     text,
  detail     text,
  url        text,
  user_agent text,
  created_at timestamptz not null default now()
);
create index if not exists audit_log_user_time_idx on public.audit_log(user_id, created_at desc);
create index if not exists audit_log_action_idx    on public.audit_log(action, created_at desc);

-- ─── row-level security (permissive starter) ─────────────────────
alter table public.suppliers            enable row level security;
alter table public.supplier_documents   enable row level security;
alter table public.inventory_items      enable row level security;
alter table public.role_templates       enable row level security;
alter table public.employees            enable row level security;
alter table public.time_sessions        enable row level security;
alter table public.user_views           enable row level security;
alter table public.audit_log            enable row level security;

-- Authenticated users get full read/write on business tables.
do $$
declare t text;
begin
  foreach t in array array['suppliers','supplier_documents','inventory_items',
                           'role_templates','employees','time_sessions']
  loop
    execute format($f$ create policy %I on public.%I for all
                       to authenticated using (true) with check (true) $f$,
                    t || '_all_auth', t);
  end loop;
end$$;

-- Saved views are owner-only.
create policy user_views_owner on public.user_views for all
  to authenticated
  using  (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- Anyone (including anon) can insert audit rows; only the owner can read.
create policy audit_log_insert_anyone on public.audit_log
  for insert to anon, authenticated with check (true);
create policy audit_log_read_own on public.audit_log
  for select to authenticated
  using (user_id = auth.uid());

-- ─── supplier-docs storage bucket ────────────────────────────────
-- Create the bucket in the Supabase Storage UI (private, name: supplier-docs)
-- then add these policies so authenticated users can upload/download:
--
--   create policy supplier_docs_all_auth on storage.objects for all
--     to authenticated
--     using  (bucket_id = 'supplier-docs')
--     with check (bucket_id = 'supplier-docs');
