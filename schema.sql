-- Nicolas Nicolas Group — Supabase schema
--
-- Run this in the Supabase SQL editor (Project → SQL → New query)
-- after you plug your real URL + anon key into config.js.
--
-- Fresh, empty deployment. RLS is enabled everywhere with permissive
-- starter policies (authenticated users can read/write). Tighten before
-- letting real users in.

create extension if not exists "pgcrypto";

-- ─── suppliers ───────────────────────────────────────────────────
create table if not exists public.suppliers (
  id                        uuid primary key default gen_random_uuid(),
  name                      text not null,
  country                   text,
  contact_name              text,
  contact_email             text,
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
-- Both `item_name` and `name` are kept as convenience aliases because
-- the inventory page reads either. Same for `unit_of_measure`/`unit`
-- and `category_name`/`category`.
create table if not exists public.inventory_items (
  id                         uuid primary key default gen_random_uuid(),
  name                       text not null,
  item_name                  text,
  description                text,
  sku                        text,
  category                   text,
  category_name              text,
  unit                       text default 'pcs',
  unit_of_measure            text,
  min_qty                    numeric default 0,
  min_stock                  numeric default 0,
  max_qty                    numeric default 0,
  monthly_consumption        numeric default 0,
  lead_time_days             integer default 0,
  storage_conditions         text,
  preferred_supplier_id      uuid references public.suppliers(id) on delete set null,
  supplier_id                uuid,
  auto_requisition_enabled   boolean default true,
  active                     boolean default true,
  is_active                  boolean default true,
  created_by                 text,
  notes                      text,
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz
);

create table if not exists public.inventory_locations (
  id            uuid primary key default gen_random_uuid(),
  location_name text not null,
  notes         text,
  created_at    timestamptz not null default now()
);

create table if not exists public.inventory_lots (
  id             uuid primary key default gen_random_uuid(),
  item_id        uuid not null references public.inventory_items(id) on delete cascade,
  item_name      text,
  lot_no         text,
  lot_number     text,
  serial_no      text,
  initial_qty    numeric default 0,
  available_qty  numeric default 0,
  quantity       numeric default 0,
  unit_cost      numeric default 0,
  purchase_date  date,
  expiry_date    date,
  min_stock      numeric default 0,
  reorder_point  numeric default 0,
  reorder_qty    numeric default 0,
  supplier_id    uuid references public.suppliers(id) on delete set null,
  location_id    uuid references public.inventory_locations(id) on delete set null,
  is_active      boolean default true,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz
);

-- Enriched view the inventory page reads for the stock table.
create or replace view public.inventory_lots_enriched_view as
select l.*,
       i.category_name,
       i.max_qty,
       s.name  as supplier_name,
       loc.location_name
from   public.inventory_lots l
left join public.inventory_items     i   on i.id  = l.item_id
left join public.suppliers           s   on s.id  = l.supplier_id
left join public.inventory_locations loc on loc.id = l.location_id;

create table if not exists public.inventory_stock_history (
  id                    uuid primary key default gen_random_uuid(),
  lot_id                uuid references public.inventory_lots(id) on delete cascade,
  item_id               uuid,
  item_name             text,
  action_type           text,           -- purchase | usage | adjustment | import
  quantity              numeric,
  unit_cost             numeric,
  reference_no          text,
  production_order_no   text,
  production_batch_id   text,
  note                  text,
  created_at            timestamptz not null default now()
);

create table if not exists public.inventory_batch_consumption (
  id                    uuid primary key default gen_random_uuid(),
  lot_id                uuid references public.inventory_lots(id) on delete cascade,
  production_order_no   text,
  production_batch_id   text,
  consumed_qty          numeric,
  note                  text,
  created_at            timestamptz not null default now()
);

-- ─── requisitions ────────────────────────────────────────────────
create table if not exists public.inventory_requisitions (
  id                   uuid primary key default gen_random_uuid(),
  requester_name       text,
  item_name            text not null,
  quantity_requested   numeric not null,
  unit                 text,
  priority             text default 'normal',
  status               text default 'pending',
  notes                text,
  generated_by         text,
  po_id                uuid,
  po_number            text,
  approved_by          text,
  approved_at          timestamptz,
  fulfilled_at         timestamptz,
  created_at           timestamptz not null default now()
);

-- ─── bill of materials ───────────────────────────────────────────
create table if not exists public.bom (
  id                   uuid primary key default gen_random_uuid(),
  material_name        text not null,
  category             text,
  unit                 text,
  qty_per_aligner      numeric,     -- kept for compat; means "qty per unit" now
  qty_basis            text default 'per_aligner',  -- per_aligner | per_case
  pack_size            numeric,
  pack_unit            text,
  safety_reserve_pct   integer default 10,
  notes                text,
  active               boolean default true,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz
);

-- ─── proforma requisitions (auto-requisition output) ─────────────
create sequence if not exists public.requisitions_seq;
create table if not exists public.requisitions (
  id             uuid primary key default gen_random_uuid(),
  requisition_no text unique default ('REQ-' || lpad(nextval('public.requisitions_seq')::text, 5, '0')),
  title          text,
  generated_by   text,
  aligners_base  integer default 0,
  status         text default 'draft',
  approved_by    text,
  approved_at    timestamptz,
  created_at     timestamptz not null default now()
);
create table if not exists public.requisition_lines (
  id               uuid primary key default gen_random_uuid(),
  requisition_id   uuid not null references public.requisitions(id) on delete cascade,
  bom_id           uuid references public.bom(id) on delete set null,
  material_name    text,
  unit             text,
  qty_needed       numeric,
  qty_in_stock     numeric,
  qty_to_order     numeric,
  pack_size        numeric,
  packs_to_order   numeric
);

-- ─── purchase orders ─────────────────────────────────────────────
create table if not exists public.purchase_orders (
  id             uuid primary key default gen_random_uuid(),
  po_number      text unique,
  supplier_id    uuid,
  supplier_name  text,
  supplier_email text,
  item_count     integer default 0,
  total_cost     numeric default 0,
  currency       text default 'EUR',
  status         text default 'sent',       -- sent | received | cancelled
  email_status   text default 'no_email',   -- pending | sent | failed | no_email
  source         text,                      -- inventory_queue | reorder | manual
  created_by     text,
  created_at     timestamptz not null default now()
);
create table if not exists public.purchase_order_lines (
  id          uuid primary key default gen_random_uuid(),
  po_id       uuid not null references public.purchase_orders(id) on delete cascade,
  item_name   text not null,
  quantity    numeric,
  unit        text,
  unit_cost   numeric,
  line_total  numeric,
  created_at  timestamptz not null default now()
);

-- ─── employees / roles ───────────────────────────────────────────
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

-- ─── settings + notifications (optional Brevo email integration) ──
create table if not exists public.system_settings (
  key        text primary key,
  value      text,
  updated_at timestamptz not null default now()
);
create table if not exists public.notification_settings (
  id                            uuid primary key default gen_random_uuid(),
  employee_name                 text,
  email                         text,
  whatsapp                      text,
  whatsapp_phone                text,
  notify_low_stock              boolean default true,
  notify_requisition_approved   boolean default true,
  is_active                     boolean default true,
  created_at                    timestamptz not null default now()
);

-- ─── production-plan side tables (empty in NN; kept for compat) ───
-- The BOM calculator reads these to compute how many units are still
-- to produce. Leave empty and the calculator simply reports zero.
create table if not exists public.bloom_cases (
  case_id        text primary key,
  current_status text,
  created_at     timestamptz not null default now()
);
create table if not exists public.bloom_aligner_details (
  id                  uuid primary key default gen_random_uuid(),
  case_number         text,
  number_of_aligners  integer,
  aligner_upper       integer,
  aligner_lower       integer,
  order_type          text
);
create table if not exists public.production_records (
  id                 uuid primary key default gen_random_uuid(),
  case_id            text,
  aligners_produced  integer default 0,
  status             text
);

-- ─── RPCs the inventory page calls ───────────────────────────────

-- FEFO lot picker: earliest expiry with available stock for an item.
create or replace function public.get_fefo_lot(p_item_id uuid)
returns table (
  lot_id        uuid,
  lot_no        text,
  available_qty numeric,
  expiry_date   date,
  unit_cost     numeric
)
language sql stable as $$
  select id as lot_id, lot_no, available_qty, expiry_date, unit_cost
  from public.inventory_lots
  where item_id = p_item_id
    and coalesce(available_qty,0) > 0
  order by expiry_date nulls last, created_at
  limit 1
$$;

-- Auto-requisition generator: per BOM entry, computes qty needed
-- (per_case entries × active case count, per_aligner × units-still-to-produce),
-- plus safety reserve, minus stock on hand.
create or replace function public.generate_auto_requisitions()
returns table (
  bom_id         uuid,
  material_name  text,
  unit           text,
  qty_needed     numeric,
  qty_in_stock   numeric,
  qty_to_order   numeric,
  pack_size      numeric,
  packs_to_order numeric
)
language plpgsql stable as $$
declare
  active_cases integer;
  units_left   integer;
begin
  select count(*) into active_cases
    from public.bloom_cases
    where coalesce(current_status,'') not in ('DELIVERED','ARCHIVE','CANCELLED');

  select greatest(0,
    coalesce((select sum(coalesce(number_of_aligners, coalesce(aligner_upper,0)+coalesce(aligner_lower,0)))
              from public.bloom_aligner_details where order_type='TreatmentPlan'),0)
    - coalesce((select sum(aligners_produced) from public.production_records where status='complete'),0))
    into units_left;

  return query
  select b.id as bom_id,
         b.material_name,
         b.unit,
         (case when b.qty_basis='per_case'
               then coalesce(b.qty_per_aligner,0) * active_cases
               else coalesce(b.qty_per_aligner,0) * units_left end
          * (1 + coalesce(b.safety_reserve_pct,0)/100.0))::numeric as qty_needed,
         coalesce((select sum(available_qty) from public.inventory_lots l
                   join public.inventory_items i on i.id = l.item_id
                   where lower(coalesce(i.item_name,i.name)) = lower(b.material_name)),0)::numeric as qty_in_stock,
         greatest(0,
           (case when b.qty_basis='per_case'
                 then coalesce(b.qty_per_aligner,0) * active_cases
                 else coalesce(b.qty_per_aligner,0) * units_left end
            * (1 + coalesce(b.safety_reserve_pct,0)/100.0))::numeric
           - coalesce((select sum(available_qty) from public.inventory_lots l
                       join public.inventory_items i on i.id = l.item_id
                       where lower(coalesce(i.item_name,i.name)) = lower(b.material_name)),0)
         )::numeric as qty_to_order,
         b.pack_size,
         case when coalesce(b.pack_size,0) > 0
              then ceil(greatest(0,
                     (case when b.qty_basis='per_case'
                           then coalesce(b.qty_per_aligner,0) * active_cases
                           else coalesce(b.qty_per_aligner,0) * units_left end
                      * (1 + coalesce(b.safety_reserve_pct,0)/100.0))::numeric
                     - coalesce((select sum(available_qty) from public.inventory_lots l
                                 join public.inventory_items i on i.id = l.item_id
                                 where lower(coalesce(i.item_name,i.name)) = lower(b.material_name)),0)
                   ) / b.pack_size)::numeric
              else null end as packs_to_order
  from public.bom b
  where b.active;
end $$;

-- ─── row-level security (permissive starter) ─────────────────────
alter table public.suppliers            enable row level security;
alter table public.supplier_documents   enable row level security;
alter table public.inventory_items      enable row level security;
alter table public.inventory_lots       enable row level security;
alter table public.inventory_locations  enable row level security;
alter table public.inventory_stock_history    enable row level security;
alter table public.inventory_batch_consumption enable row level security;
alter table public.inventory_requisitions enable row level security;
alter table public.bom                  enable row level security;
alter table public.requisitions         enable row level security;
alter table public.requisition_lines    enable row level security;
alter table public.purchase_orders      enable row level security;
alter table public.purchase_order_lines enable row level security;
alter table public.role_templates       enable row level security;
alter table public.employees            enable row level security;
alter table public.time_sessions        enable row level security;
alter table public.user_views           enable row level security;
alter table public.audit_log            enable row level security;
alter table public.system_settings      enable row level security;
alter table public.notification_settings enable row level security;
alter table public.bloom_cases          enable row level security;
alter table public.bloom_aligner_details enable row level security;
alter table public.production_records   enable row level security;

do $$
declare t text;
begin
  foreach t in array array[
    'suppliers','supplier_documents',
    'inventory_items','inventory_lots','inventory_locations',
    'inventory_stock_history','inventory_batch_consumption','inventory_requisitions',
    'bom','requisitions','requisition_lines',
    'purchase_orders','purchase_order_lines',
    'role_templates','employees','time_sessions',
    'system_settings','notification_settings',
    'bloom_cases','bloom_aligner_details','production_records'
  ]
  loop
    execute format($f$ create policy %I on public.%I for all
                       to authenticated using (true) with check (true) $f$,
                    t || '_all_auth', t);
  end loop;
end$$;

create policy user_views_owner on public.user_views for all
  to authenticated
  using  (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy audit_log_insert_anyone on public.audit_log
  for insert to anon, authenticated with check (true);
create policy audit_log_read_own on public.audit_log
  for select to authenticated
  using (user_id = auth.uid());

-- ─── supplier-docs storage bucket ────────────────────────────────
-- Create the bucket in the Supabase Storage UI (private, name: supplier-docs)
-- then add this policy so authenticated users can upload/download:
--
--   create policy supplier_docs_all_auth on storage.objects for all
--     to authenticated
--     using  (bucket_id = 'supplier-docs')
--     with check (bucket_id = 'supplier-docs');
