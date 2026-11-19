-- =====================================================================
-- EZ ERP - Migration 0002: Master data
-- Customers and suppliers (parties), products and services, warehouses,
-- tax rates, product image storage.
-- Requires 0001_core.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tax rates (configurable; no rate is assumed to be legally correct)
-- ---------------------------------------------------------------------
create table public.tax_rates (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  rate numeric(7,3) not null default 0 check (rate >= 0 and rate <= 100),
  applies_to text not null default 'both' check (applies_to in ('sales', 'purchase', 'both')),
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, name)
);
create trigger tax_rates_updated before update on public.tax_rates
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- Parties: one table for customers and suppliers
-- ---------------------------------------------------------------------
create table public.parties (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  code text,
  is_customer boolean not null default false,
  is_supplier boolean not null default false,
  party_type text not null default 'company' check (party_type in ('individual', 'company')),
  name text not null,
  contact_person text,
  email text,
  phone text,
  website text,
  address_line text,
  division text,
  district text,
  upazila text,
  area text,
  postal_code text,
  shipping_address text,
  trade_license_no text,
  tax_id text,
  customer_group_id uuid references public.lookups(id) on delete set null,
  supplier_category_id uuid references public.lookups(id) on delete set null,
  credit_limit numeric(18,2) check (credit_limit is null or credit_limit >= 0),
  payment_terms_days int check (payment_terms_days is null or payment_terms_days >= 0),
  opening_receivable numeric(18,2) not null default 0,
  opening_payable numeric(18,2) not null default 0,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (is_customer or is_supplier)
);
create unique index parties_code_unique on public.parties(org_id, code);
create index parties_kind_idx on public.parties(org_id, is_customer, is_supplier);
create trigger parties_updated before update on public.parties
  for each row execute function public.set_updated_at();

create or replace function public.parties_defaults()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.code is null or btrim(new.code) = '' then
    new.code := public.next_doc_number(new.org_id, case when new.is_customer then 'customer' else 'supplier' end);
  end if;
  return new;
end $$;
create trigger parties_defaults before insert on public.parties
  for each row execute function public.parties_defaults();

-- ---------------------------------------------------------------------
-- Warehouses
-- ---------------------------------------------------------------------
create table public.warehouses (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  code text not null,
  name text not null,
  branch_id uuid references public.branches(id) on delete set null,
  address_line text,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, code)
);
create trigger warehouses_updated before update on public.warehouses
  for each row execute function public.set_updated_at();

-- Only one default warehouse per organization.
create or replace function public.warehouses_single_default()
returns trigger language plpgsql as $$
begin
  if new.is_default then
    update public.warehouses set is_default = false
    where org_id = new.org_id and id <> new.id and is_default;
  end if;
  return new;
end $$;
create trigger warehouses_single_default after insert or update of is_default on public.warehouses
  for each row when (new.is_default) execute function public.warehouses_single_default();

-- ---------------------------------------------------------------------
-- Products and services
-- ---------------------------------------------------------------------
create table public.products (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  item_type text not null default 'product'
    check (item_type in ('product', 'service', 'raw_material', 'asset')),
  sku text,
  barcode text,
  name text not null,
  description text,
  category_id uuid references public.lookups(id) on delete set null,
  brand_id uuid references public.lookups(id) on delete set null,
  unit_id uuid references public.lookups(id) on delete set null,
  tax_rate_id uuid references public.tax_rates(id) on delete set null,
  purchase_price numeric(18,2) not null default 0 check (purchase_price >= 0),
  sales_price numeric(18,2) not null default 0 check (sales_price >= 0),
  standard_cost numeric(18,2) not null default 0 check (standard_cost >= 0),
  track_inventory boolean not null default true,
  min_stock numeric(18,3) not null default 0 check (min_stock >= 0),
  reorder_level numeric(18,3) not null default 0 check (reorder_level >= 0),
  image_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index products_sku_unique on public.products(org_id, sku);
create unique index products_barcode_unique on public.products(org_id, barcode) where barcode is not null;
create index products_name_idx on public.products(org_id, name);
create trigger products_updated before update on public.products
  for each row execute function public.set_updated_at();

create or replace function public.products_defaults()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.sku is null or btrim(new.sku) = '' then
    new.sku := public.next_doc_number(new.org_id, 'product');
  end if;
  if new.item_type = 'service' then
    new.track_inventory := false;
  end if;
  return new;
end $$;
create trigger products_defaults before insert or update on public.products
  for each row execute function public.products_defaults();

-- ---------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------
select public.apply_org_rls('public.tax_rates', 'settings', true);
select public.apply_org_rls('public.warehouses', 'inventory', true);

-- Customers are governed by the sales permission, suppliers by purchase.
alter table public.parties enable row level security;
create policy parties_select on public.parties for select to authenticated using (
  (is_customer and public.has_permission(org_id, 'sales', 'view'))
  or (is_supplier and public.has_permission(org_id, 'purchase', 'view')));
create policy parties_insert on public.parties for insert to authenticated with check (
  (is_customer and public.has_permission(org_id, 'sales', 'create'))
  or (is_supplier and public.has_permission(org_id, 'purchase', 'create')));
create policy parties_update on public.parties for update to authenticated using (
  (is_customer and public.has_permission(org_id, 'sales', 'edit'))
  or (is_supplier and public.has_permission(org_id, 'purchase', 'edit')))
  with check (
  (is_customer and public.has_permission(org_id, 'sales', 'edit'))
  or (is_supplier and public.has_permission(org_id, 'purchase', 'edit')));
create policy parties_delete on public.parties for delete to authenticated using (
  (is_customer and public.has_permission(org_id, 'sales', 'delete'))
  or (is_supplier and public.has_permission(org_id, 'purchase', 'delete')));

-- Products are read by anyone who sells, buys, requests or stocks items.
alter table public.products enable row level security;
create policy products_select on public.products for select to authenticated using (
  public.has_permission(org_id, 'inventory', 'view')
  or public.has_permission(org_id, 'sales', 'view')
  or public.has_permission(org_id, 'purchase', 'view')
  or public.has_permission(org_id, 'requisitions', 'view'));
create policy products_insert on public.products for insert to authenticated
  with check (public.has_permission(org_id, 'inventory', 'create'));
create policy products_update on public.products for update to authenticated
  using (public.has_permission(org_id, 'inventory', 'edit'))
  with check (public.has_permission(org_id, 'inventory', 'edit'));
create policy products_delete on public.products for delete to authenticated
  using (public.has_permission(org_id, 'inventory', 'delete'));

select public.enable_audit('public.parties');
select public.enable_audit('public.products');
select public.enable_audit('public.warehouses');
select public.enable_audit('public.tax_rates');

-- ---------------------------------------------------------------------
-- Defaults for every new organization (runs after the core seed)
-- ---------------------------------------------------------------------
create or replace function public.seed_org_masters()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform set_config('app.skip_audit', 'on', true);

  insert into warehouses (org_id, code, name, branch_id, is_default)
  select new.id, 'MAIN', 'Main Warehouse', b.id, true
  from branches b where b.org_id = new.id and b.is_head_office;

  insert into tax_rates (org_id, name, rate, applies_to, description)
  values (new.id, 'No tax', 0, 'both', 'Zero rate. Add the rates that apply to your business under Business settings.');

  perform set_config('app.skip_audit', 'off', true);
  return new;
end $$;

-- Named so it fires after trg_seed_org_core (triggers run alphabetically).
create trigger trg_seed_org_masters after insert on public.organizations
  for each row execute function public.seed_org_masters();

-- Backfill organizations created before this migration.
do $$
declare o record;
begin
  perform set_config('app.skip_audit', 'on', true);
  for o in select id from organizations loop
    insert into warehouses (org_id, code, name, branch_id, is_default)
    select o.id, 'MAIN', 'Main Warehouse', b.id, true
    from branches b
    where b.org_id = o.id and b.is_head_office
      and not exists (select 1 from warehouses w where w.org_id = o.id);
    insert into tax_rates (org_id, name, rate, applies_to, description)
    select o.id, 'No tax', 0, 'both', 'Zero rate. Add the rates that apply to your business under Business settings.'
    where not exists (select 1 from tax_rates t where t.org_id = o.id);
  end loop;
  perform set_config('app.skip_audit', 'off', true);
end $$;

-- ---------------------------------------------------------------------
-- Product image storage (public read, inventory managers write)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('product-images', 'product-images', true)
  on conflict (id) do nothing;

create policy product_images_write on storage.objects for insert to authenticated
  with check (bucket_id = 'product-images'
              and public.has_permission(((storage.foldername(name))[1])::uuid, 'inventory', 'edit'));
create policy product_images_update on storage.objects for update to authenticated
  using (bucket_id = 'product-images'
         and public.has_permission(((storage.foldername(name))[1])::uuid, 'inventory', 'edit'));
create policy product_images_remove on storage.objects for delete to authenticated
  using (bucket_id = 'product-images'
         and public.has_permission(((storage.foldername(name))[1])::uuid, 'inventory', 'edit'));
