-- =====================================================================
-- EZ ERP - Migration 0001: Core platform
-- Multi-tenant foundation: organizations, members, roles and permissions,
-- branches, departments, lookups, numbering, audit log, notifications,
-- attachments and storage buckets.
-- =====================================================================

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- Profiles (one per auth user)
-- ---------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  phone text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger profiles_updated before update on public.profiles
  for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- Organizations (a company / legal entity - the tenant boundary)
-- ---------------------------------------------------------------------
create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  legal_name text,
  logo_url text,
  business_type text,
  email text,
  phone text,
  website text,
  address_line text,
  division text,
  district text,
  upazila text,
  area text,
  postal_code text,
  country_code text not null default 'BD',
  trade_license_no text,
  tax_id text,
  currency_code text not null default 'BDT',
  date_format text not null default 'dd MMM yyyy',
  timezone text not null default 'Asia/Dhaka',
  language text not null default 'en',
  fiscal_year_start_month int not null default 7
    check (fiscal_year_start_month between 1 and 12),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger organizations_updated before update on public.organizations
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- Branches and departments
-- ---------------------------------------------------------------------
create table public.branches (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  code text not null,
  name text not null,
  branch_type text not null default 'branch'
    check (branch_type in ('head_office', 'branch', 'outlet', 'office')),
  phone text,
  email text,
  address_line text,
  district text,
  is_head_office boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, code),
  check (not (is_head_office and not is_active))
);
create unique index branches_one_head_office on public.branches(org_id) where is_head_office;
create trigger branches_updated before update on public.branches
  for each row execute function public.set_updated_at();

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  description text,
  head_user_id uuid references public.profiles(id) on delete set null,
  parent_id uuid references public.departments(id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, name)
);
create trigger departments_updated before update on public.departments
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- Roles, permissions, members, invitations
-- ---------------------------------------------------------------------
create table public.roles (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  description text,
  is_system boolean not null default false,
  is_owner boolean not null default false,
  created_at timestamptz not null default now(),
  unique (org_id, name)
);

create table public.role_permissions (
  org_id uuid not null references public.organizations(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete cascade,
  module text not null,
  can_view boolean not null default false,
  can_create boolean not null default false,
  can_edit boolean not null default false,
  can_delete boolean not null default false,
  can_approve boolean not null default false,
  can_export boolean not null default false,
  primary key (role_id, module)
);

create table public.organization_members (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role_id uuid not null references public.roles(id),
  department_id uuid references public.departments(id) on delete set null,
  branch_ids uuid[] not null default '{}',
  status text not null default 'active' check (status in ('active', 'suspended', 'revoked')),
  joined_at timestamptz not null default now(),
  unique (org_id, user_id)
);
create index organization_members_user_idx on public.organization_members(user_id);

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  email text not null,
  role_id uuid not null references public.roles(id) on delete cascade,
  branch_ids uuid[] not null default '{}',
  status text not null default 'pending' check (status in ('pending', 'accepted', 'revoked')),
  invited_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  accepted_at timestamptz
);
create unique index invitations_pending_email on public.invitations(org_id, lower(email))
  where status = 'pending';

-- ---------------------------------------------------------------------
-- Lookups (units, categories, brands, payment methods ...), numbering
-- ---------------------------------------------------------------------
create table public.lookups (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  kind text not null check (kind in (
    'customer_group', 'supplier_category', 'product_category', 'brand',
    'unit', 'payment_method', 'document_category')),
  name text not null,
  code text,
  parent_id uuid references public.lookups(id) on delete set null,
  meta jsonb not null default '{}'::jsonb,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (org_id, kind, name)
);

create table public.doc_sequences (
  org_id uuid not null references public.organizations(id) on delete cascade,
  doc_type text not null,
  prefix text not null,
  next_number bigint not null default 1,
  padding int not null default 5 check (padding between 1 and 12),
  primary key (org_id, doc_type)
);

-- ---------------------------------------------------------------------
-- Audit log, notifications, attachments
-- ---------------------------------------------------------------------
create table public.audit_logs (
  id bigint generated always as identity primary key,
  org_id uuid references public.organizations(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete set null,
  table_name text not null,
  record_id text,
  action text not null,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);
create index audit_logs_org_idx on public.audit_logs(org_id, created_at desc);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text,
  kind text not null default 'info',
  entity_type text,
  entity_id uuid,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications(user_id, created_at desc);

create table public.attachments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  file_name text not null,
  storage_path text not null,
  mime_type text,
  size_bytes bigint,
  uploaded_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index attachments_entity_idx on public.attachments(org_id, entity_type, entity_id);

-- ---------------------------------------------------------------------
-- Access helpers (security definer so they can be used inside RLS)
-- ---------------------------------------------------------------------
create or replace function public.is_org_member(p_org uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from organization_members m
    where m.org_id = p_org and m.user_id = auth.uid() and m.status = 'active'
  );
$$;

create or replace function public.has_permission(p_org uuid, p_module text, p_action text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(bool_or(
    r.is_owner or coalesce(case p_action
      when 'view' then rp.can_view
      when 'create' then rp.can_create
      when 'edit' then rp.can_edit
      when 'delete' then rp.can_delete
      when 'approve' then rp.can_approve
      when 'export' then rp.can_export
      else false end, false)
  ), false)
  from organization_members m
  join roles r on r.id = m.role_id
  left join role_permissions rp on rp.role_id = r.id and rp.module = p_module
  where m.org_id = p_org and m.user_id = auth.uid() and m.status = 'active';
$$;

create or replace function public.shares_org_with(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from organization_members a
    join organization_members b on b.org_id = a.org_id
    where a.user_id = auth.uid() and a.status = 'active' and b.user_id = p_user
  );
$$;

-- Standard org-scoped RLS: one call per table.
-- p_read_any_member = true lets every active member read (dropdown data).
create or replace function public.apply_org_rls(p_table regclass, p_module text, p_read_any_member boolean default false)
returns void language plpgsql as $$
begin
  execute format('alter table %s enable row level security', p_table);
  execute format('drop policy if exists org_select on %s', p_table);
  execute format('drop policy if exists org_insert on %s', p_table);
  execute format('drop policy if exists org_update on %s', p_table);
  execute format('drop policy if exists org_delete on %s', p_table);
  if p_read_any_member then
    execute format('create policy org_select on %s for select to authenticated using (public.is_org_member(org_id))', p_table);
  else
    execute format('create policy org_select on %s for select to authenticated using (public.has_permission(org_id, %L, ''view''))', p_table, p_module);
  end if;
  execute format('create policy org_insert on %s for insert to authenticated with check (public.has_permission(org_id, %L, ''create''))', p_table, p_module);
  execute format('create policy org_update on %s for update to authenticated using (public.has_permission(org_id, %L, ''edit'')) with check (public.has_permission(org_id, %L, ''edit''))', p_table, p_module, p_module);
  execute format('create policy org_delete on %s for delete to authenticated using (public.has_permission(org_id, %L, ''delete''))', p_table, p_module);
end $$;

-- ---------------------------------------------------------------------
-- Audit trail
-- ---------------------------------------------------------------------
create or replace function public.audit_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_row jsonb;
  v_old jsonb;
  v_org uuid;
begin
  if coalesce(current_setting('app.skip_audit', true), '') = 'on' then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  if tg_op = 'DELETE' then
    v_row := to_jsonb(old);
    v_old := v_row;
  elsif tg_op = 'UPDATE' then
    v_row := to_jsonb(new);
    v_old := to_jsonb(old);
  else
    v_row := to_jsonb(new);
  end if;

  v_org := nullif(v_row->>'org_id', '')::uuid;
  if v_org is null and tg_table_name = 'organizations' then
    v_org := (v_row->>'id')::uuid;
  end if;

  insert into audit_logs (org_id, user_id, table_name, record_id, action, old_data, new_data)
  values (
    v_org, auth.uid(), tg_table_name,
    coalesce(v_row->>'id', v_row->>'role_id'),
    tg_op, v_old,
    case when tg_op = 'DELETE' then null else v_row end
  );

  if tg_op = 'DELETE' then return old; else return new; end if;
end $$;

create or replace function public.enable_audit(p_table regclass)
returns void language plpgsql as $$
begin
  execute format('drop trigger if exists audit_row on %s', p_table);
  execute format('create trigger audit_row after insert or update or delete on %s for each row execute function public.audit_trigger()', p_table);
end $$;

-- ---------------------------------------------------------------------
-- Guard rails for membership changes
-- ---------------------------------------------------------------------
create or replace function public.protect_member_roles()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_org uuid;
  v_new_owner boolean := false;
  v_old_owner boolean := false;
  v_caller_owner boolean := false;
  v_leaving boolean := false;
begin
  if coalesce(current_setting('app.bootstrap', true), '') = 'on' then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  v_org := case when tg_op = 'DELETE' then old.org_id else new.org_id end;

  if tg_op <> 'DELETE' then
    select r.is_owner into v_new_owner from roles r
    where r.id = new.role_id and r.org_id = new.org_id;
    if not found then
      raise exception 'Role does not belong to this organization';
    end if;
  end if;

  if tg_op <> 'INSERT' then
    select r.is_owner into v_old_owner from roles r where r.id = old.role_id;
  end if;

  select exists (
    select 1 from organization_members m join roles r on r.id = m.role_id
    where m.org_id = v_org and m.user_id = auth.uid() and m.status = 'active' and r.is_owner
  ) into v_caller_owner;

  if (v_new_owner or v_old_owner) and not v_caller_owner then
    raise exception 'Only an owner can assign or change owner access';
  end if;

  if v_old_owner then
    if tg_op = 'DELETE' then
      v_leaving := true;
    else
      v_leaving := (not v_new_owner) or new.status <> 'active';
    end if;
    if v_leaving and not exists (
      select 1 from organization_members m join roles r on r.id = m.role_id
      where m.org_id = v_org and m.id <> old.id and m.status = 'active' and r.is_owner
    ) then
      raise exception 'An organization must keep at least one active owner';
    end if;
  end if;

  if tg_op = 'DELETE' then return old; else return new; end if;
end $$;

create trigger protect_member_roles before insert or update or delete on public.organization_members
  for each row execute function public.protect_member_roles();

-- ---------------------------------------------------------------------
-- Defaults seeded for every new organization
-- ---------------------------------------------------------------------
create or replace function public.seed_org_core()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_defs jsonb := '[
    {"name":"Director / Executive","description":"Company-wide visibility, approvals and department reports","perms":{"dashboard":"v","sales":"vax","purchase":"vax","requisitions":"v","inventory":"vx","finance":"vax","expenses":"vax","projects":"va","assets":"v","service":"v","documents":"v","reports":"vx","approvals":"va","hr_admin":"v","branches":"v","settings":"v","audit":"v","financial_data":"v"}},
    {"name":"General Manager","description":"Day-to-day operations across all departments","perms":{"dashboard":"v","sales":"vceax","purchase":"vceax","requisitions":"vceax","inventory":"vceax","finance":"vx","expenses":"vceax","projects":"vceax","assets":"vce","service":"vce","documents":"vce","reports":"vx","approvals":"va","hr_admin":"v","branches":"v","settings":"v","financial_data":"v"}},
    {"name":"Accounts Manager","description":"Accounting, vouchers, banking and financial reports","perms":{"dashboard":"v","sales":"v","purchase":"v","finance":"vcedax","expenses":"vcedax","assets":"v","documents":"vce","reports":"vx","approvals":"va","financial_data":"v"}},
    {"name":"Accountant","description":"Records vouchers, payments and expenses","perms":{"dashboard":"v","sales":"v","purchase":"v","finance":"vce","expenses":"vce","documents":"vc","reports":"v","approvals":"v","financial_data":"v"}},
    {"name":"Purchase Manager","description":"Suppliers, requisitions, purchase orders and bills","perms":{"dashboard":"v","purchase":"vcedax","requisitions":"vceax","inventory":"v","expenses":"vc","documents":"vce","reports":"v","approvals":"va"}},
    {"name":"Sales Manager","description":"Customers, quotations, orders and invoices","perms":{"dashboard":"v","sales":"vcedax","inventory":"v","finance":"v","expenses":"vc","documents":"vce","reports":"v","approvals":"va","financial_data":"v"}},
    {"name":"Inventory / Store Manager","description":"Warehouses, stock and stock movements","perms":{"dashboard":"v","inventory":"vcedax","purchase":"vc","requisitions":"vc","documents":"vc","reports":"v","approvals":"v"}},
    {"name":"Project Manager","description":"Projects, tasks, budgets and deadlines","perms":{"dashboard":"v","projects":"vcedax","requisitions":"vc","expenses":"vc","documents":"vce","reports":"v","approvals":"v","hr_admin":"v"}},
    {"name":"Department Head","description":"Own department work, team and approvals","perms":{"dashboard":"v","requisitions":"vcea","expenses":"vca","projects":"vce","documents":"v","reports":"v","approvals":"va","hr_admin":"v"}},
    {"name":"Employee / Staff","description":"Assigned work, requests and limited information","perms":{"dashboard":"v","requisitions":"vc","expenses":"vc","projects":"v","documents":"v","approvals":"v"}},
    {"name":"Auditor / Viewer","description":"Read-only access to approved reports and records","perms":{"dashboard":"v","sales":"vx","purchase":"vx","requisitions":"v","inventory":"vx","finance":"vx","expenses":"v","projects":"v","assets":"v","service":"v","documents":"vx","reports":"vx","approvals":"v","hr_admin":"v","branches":"v","audit":"vx","financial_data":"v"}}
  ]'::jsonb;
  r jsonb;
  m record;
  v_role uuid;
begin
  perform set_config('app.skip_audit', 'on', true);

  insert into branches (org_id, code, name, branch_type, is_head_office)
  values (new.id, 'HO', 'Head Office', 'head_office', true);

  insert into roles (org_id, name, description, is_system, is_owner)
  values (new.id, 'Owner', 'Full control of the organization, settings, users and reports', true, true);

  for r in select * from jsonb_array_elements(v_defs) loop
    insert into roles (org_id, name, description, is_system)
    values (new.id, r->>'name', r->>'description', true)
    returning id into v_role;

    for m in select key as module, value #>> '{}' as p from jsonb_each(r->'perms') loop
      insert into role_permissions
        (org_id, role_id, module, can_view, can_create, can_edit, can_delete, can_approve, can_export)
      values (
        new.id, v_role, m.module,
        position('v' in m.p) > 0, position('c' in m.p) > 0, position('e' in m.p) > 0,
        position('d' in m.p) > 0, position('a' in m.p) > 0, position('x' in m.p) > 0
      );
    end loop;
  end loop;

  insert into lookups (org_id, kind, name, sort_order)
  select new.id, t.k, t.n, t.o from (values
    ('unit', 'Pcs', 1), ('unit', 'Dozen', 2), ('unit', 'Hali', 3), ('unit', 'Pair', 4),
    ('unit', 'Set', 5), ('unit', 'Box', 6), ('unit', 'Carton', 7), ('unit', 'Pack', 8),
    ('unit', 'Bag', 9), ('unit', 'Kg', 10), ('unit', 'Gram', 11), ('unit', 'Maund', 12),
    ('unit', 'Ton', 13), ('unit', 'Litre', 14), ('unit', 'Meter', 15), ('unit', 'Feet', 16),
    ('unit', 'Hour', 17), ('unit', 'Service', 18),
    ('payment_method', 'Cash', 1), ('payment_method', 'Bank Transfer', 2),
    ('payment_method', 'Cheque', 3), ('payment_method', 'Card', 4),
    ('payment_method', 'bKash', 5), ('payment_method', 'Nagad', 6), ('payment_method', 'Rocket', 7),
    ('customer_group', 'Retail', 1), ('customer_group', 'Wholesale', 2), ('customer_group', 'Corporate', 3),
    ('supplier_category', 'Raw Materials', 1), ('supplier_category', 'Finished Goods', 2),
    ('supplier_category', 'Services', 3),
    ('document_category', 'Contracts', 1), ('document_category', 'Licenses', 2),
    ('document_category', 'Tax and VAT', 3), ('document_category', 'Invoices and Bills', 4)
  ) as t(k, n, o);

  insert into doc_sequences (org_id, doc_type, prefix)
  select new.id, s.t, s.p from (values
    ('journal', 'JV'), ('payment', 'PV'), ('receipt', 'RV'), ('contra', 'CV'),
    ('debit_note', 'DN'), ('credit_note', 'CN'), ('purchase_requisition', 'PR'),
    ('purchase_order', 'PO'), ('goods_receipt', 'GRN'), ('supplier_bill', 'BILL'),
    ('sales_quotation', 'QT'), ('sales_order', 'SO'), ('sales_invoice', 'INV'),
    ('delivery_challan', 'DC'), ('expense', 'EXP'), ('income', 'INC'),
    ('stock_adjustment', 'ADJ'), ('stock_transfer', 'TRF'),
    ('customer', 'CUS'), ('supplier', 'SUP'), ('product', 'ITM')
  ) as s(t, p);

  perform set_config('app.skip_audit', 'off', true);
  return new;
end $$;

create trigger trg_seed_org_core after insert on public.organizations
  for each row execute function public.seed_org_core();

-- ---------------------------------------------------------------------
-- RPC: create organization, claim invitations, numbering, notifications
-- ---------------------------------------------------------------------
create or replace function public.create_organization(
  p_name text,
  p_business_type text default null,
  p_phone text default null,
  p_email text default null,
  p_division text default null,
  p_district text default null,
  p_currency text default 'BDT',
  p_fiscal_year_start_month int default 7
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_org uuid;
  v_role uuid;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Company name is required'; end if;

  insert into organizations
    (name, business_type, phone, email, division, district, currency_code, fiscal_year_start_month, created_by)
  values
    (trim(p_name), p_business_type, p_phone, p_email, p_division, p_district,
     upper(coalesce(p_currency, 'BDT')), coalesce(p_fiscal_year_start_month, 7), v_uid)
  returning id into v_org;

  select id into v_role from roles where org_id = v_org and is_owner limit 1;

  perform set_config('app.bootstrap', 'on', true);
  insert into organization_members (org_id, user_id, role_id) values (v_org, v_uid, v_role);
  perform set_config('app.bootstrap', 'off', true);

  return v_org;
end $$;

create or replace function public.claim_invitations()
returns int language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_count int := 0;
  r record;
begin
  if v_uid is null then return 0; end if;
  select lower(email) into v_email from auth.users where id = v_uid;
  for r in select * from invitations where status = 'pending' and lower(email) = v_email loop
    insert into organization_members (org_id, user_id, role_id, branch_ids)
    values (r.org_id, v_uid, r.role_id, r.branch_ids)
    on conflict (org_id, user_id) do update
      set status = 'active', role_id = excluded.role_id, branch_ids = excluded.branch_ids;
    update invitations set status = 'accepted', accepted_at = now() where id = r.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

create or replace function public.next_doc_number(p_org uuid, p_type text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_prefix text;
  v_num bigint;
  v_pad int;
begin
  if not public.is_org_member(p_org) then raise exception 'Access denied'; end if;
  insert into doc_sequences (org_id, doc_type, prefix)
  values (p_org, p_type, upper(left(p_type, 3)))
  on conflict (org_id, doc_type) do nothing;

  -- Counter bumps are not audit-worthy; edits to prefix/padding still are.
  perform set_config('app.skip_audit', 'on', true);
  update doc_sequences set next_number = next_number + 1
  where org_id = p_org and doc_type = p_type
  returning prefix, next_number - 1, padding into v_prefix, v_num, v_pad;
  perform set_config('app.skip_audit', 'off', true);

  return v_prefix || '-' || lpad(v_num::text, v_pad, '0');
end $$;

create or replace function public.notify_members_with_permission(
  p_org uuid, p_module text, p_action text, p_title text, p_body text default null,
  p_kind text default 'info', p_entity_type text default null, p_entity_id uuid default null
) returns int language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  if not public.is_org_member(p_org) then raise exception 'Access denied'; end if;
  insert into notifications (org_id, user_id, title, body, kind, entity_type, entity_id)
  select p_org, m.user_id, p_title, p_body, p_kind, p_entity_type, p_entity_id
  from organization_members m
  join roles r on r.id = m.role_id
  left join role_permissions rp on rp.role_id = r.id and rp.module = p_module
  where m.org_id = p_org and m.status = 'active' and m.user_id <> auth.uid()
    and (r.is_owner or coalesce(case p_action
      when 'view' then rp.can_view
      when 'create' then rp.can_create
      when 'edit' then rp.can_edit
      when 'approve' then rp.can_approve
      else false end, false));
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke execute on function public.create_organization(text, text, text, text, text, text, text, int) from public, anon;
revoke execute on function public.claim_invitations() from public, anon;
revoke execute on function public.next_doc_number(uuid, text) from public, anon;
revoke execute on function public.notify_members_with_permission(uuid, text, text, text, text, text, text, uuid) from public, anon;
grant execute on function public.create_organization(text, text, text, text, text, text, text, int) to authenticated;
grant execute on function public.claim_invitations() to authenticated;
grant execute on function public.next_doc_number(uuid, text) to authenticated;
grant execute on function public.notify_members_with_permission(uuid, text, text, text, text, text, text, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------
alter table public.profiles enable row level security;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.shares_org_with(id));
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

alter table public.organizations enable row level security;
create policy organizations_select on public.organizations for select to authenticated
  using (public.is_org_member(id));
create policy organizations_update on public.organizations for update to authenticated
  using (public.has_permission(id, 'settings', 'edit'))
  with check (public.has_permission(id, 'settings', 'edit'));

alter table public.roles enable row level security;
create policy roles_select on public.roles for select to authenticated
  using (public.is_org_member(org_id));
create policy roles_insert on public.roles for insert to authenticated
  with check (public.has_permission(org_id, 'users', 'create') and not is_system and not is_owner);
create policy roles_update on public.roles for update to authenticated
  using (public.has_permission(org_id, 'users', 'edit') and not is_owner)
  with check (public.has_permission(org_id, 'users', 'edit') and not is_owner);
create policy roles_delete on public.roles for delete to authenticated
  using (public.has_permission(org_id, 'users', 'delete') and not is_system);

alter table public.role_permissions enable row level security;
create policy rp_select on public.role_permissions for select to authenticated
  using (public.is_org_member(org_id));
create policy rp_insert on public.role_permissions for insert to authenticated
  with check (
    public.has_permission(org_id, 'users', 'edit')
    and exists (select 1 from public.roles r
                where r.id = role_permissions.role_id and r.org_id = role_permissions.org_id and not r.is_owner));
create policy rp_update on public.role_permissions for update to authenticated
  using (
    public.has_permission(org_id, 'users', 'edit')
    and exists (select 1 from public.roles r
                where r.id = role_permissions.role_id and r.org_id = role_permissions.org_id and not r.is_owner))
  with check (
    public.has_permission(org_id, 'users', 'edit')
    and exists (select 1 from public.roles r
                where r.id = role_permissions.role_id and r.org_id = role_permissions.org_id and not r.is_owner));
create policy rp_delete on public.role_permissions for delete to authenticated
  using (
    public.has_permission(org_id, 'users', 'edit')
    and exists (select 1 from public.roles r
                where r.id = role_permissions.role_id and r.org_id = role_permissions.org_id and not r.is_owner));

alter table public.organization_members enable row level security;
create policy members_select on public.organization_members for select to authenticated
  using (user_id = auth.uid() or public.has_permission(org_id, 'users', 'view'));
create policy members_insert on public.organization_members for insert to authenticated
  with check (public.has_permission(org_id, 'users', 'create'));
create policy members_update on public.organization_members for update to authenticated
  using (public.has_permission(org_id, 'users', 'edit'))
  with check (public.has_permission(org_id, 'users', 'edit'));
create policy members_delete on public.organization_members for delete to authenticated
  using (public.has_permission(org_id, 'users', 'delete'));

alter table public.invitations enable row level security;
create policy inv_select on public.invitations for select to authenticated
  using (public.has_permission(org_id, 'users', 'view'));
create policy inv_insert on public.invitations for insert to authenticated
  with check (
    public.has_permission(org_id, 'users', 'create')
    and exists (select 1 from public.roles r
                where r.id = invitations.role_id and r.org_id = invitations.org_id and not r.is_owner));
create policy inv_update on public.invitations for update to authenticated
  using (public.has_permission(org_id, 'users', 'edit'))
  with check (
    public.has_permission(org_id, 'users', 'edit')
    and exists (select 1 from public.roles r
                where r.id = invitations.role_id and r.org_id = invitations.org_id and not r.is_owner));
create policy inv_delete on public.invitations for delete to authenticated
  using (public.has_permission(org_id, 'users', 'delete'));

select public.apply_org_rls('public.branches', 'settings', true);
select public.apply_org_rls('public.departments', 'settings', true);
select public.apply_org_rls('public.lookups', 'settings', true);
select public.apply_org_rls('public.doc_sequences', 'settings', true);

alter table public.audit_logs enable row level security;
create policy audit_select on public.audit_logs for select to authenticated
  using (public.has_permission(org_id, 'audit', 'view'));

alter table public.notifications enable row level security;
create policy notif_select on public.notifications for select to authenticated using (user_id = auth.uid());
create policy notif_update on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notif_delete on public.notifications for delete to authenticated using (user_id = auth.uid());

alter table public.attachments enable row level security;
create policy att_select on public.attachments for select to authenticated
  using (public.is_org_member(org_id));
create policy att_insert on public.attachments for insert to authenticated
  with check (public.is_org_member(org_id) and uploaded_by = auth.uid());
create policy att_delete on public.attachments for delete to authenticated
  using (uploaded_by = auth.uid() or public.has_permission(org_id, 'documents', 'delete'));

-- Audit triggers
select public.enable_audit('public.organizations');
select public.enable_audit('public.branches');
select public.enable_audit('public.departments');
select public.enable_audit('public.roles');
select public.enable_audit('public.role_permissions');
select public.enable_audit('public.organization_members');
select public.enable_audit('public.invitations');
select public.enable_audit('public.lookups');
select public.enable_audit('public.doc_sequences');

-- ---------------------------------------------------------------------
-- Realtime and storage
-- ---------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.notifications;
exception when others then null;
end $$;

insert into storage.buckets (id, name, public) values ('attachments', 'attachments', false)
  on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('org-assets', 'org-assets', true)
  on conflict (id) do nothing;

-- Files live under "<org_id>/..." so the first folder identifies the tenant.
create policy attachments_read on storage.objects for select to authenticated
  using (bucket_id = 'attachments' and public.is_org_member(((storage.foldername(name))[1])::uuid));
create policy attachments_write on storage.objects for insert to authenticated
  with check (bucket_id = 'attachments' and public.is_org_member(((storage.foldername(name))[1])::uuid));
create policy attachments_remove on storage.objects for delete to authenticated
  using (bucket_id = 'attachments'
         and public.has_permission(((storage.foldername(name))[1])::uuid, 'documents', 'delete'));

create policy org_assets_write on storage.objects for insert to authenticated
  with check (bucket_id = 'org-assets'
              and public.has_permission(((storage.foldername(name))[1])::uuid, 'settings', 'edit'));
create policy org_assets_update on storage.objects for update to authenticated
  using (bucket_id = 'org-assets'
         and public.has_permission(((storage.foldername(name))[1])::uuid, 'settings', 'edit'));
create policy org_assets_remove on storage.objects for delete to authenticated
  using (bucket_id = 'org-assets'
         and public.has_permission(((storage.foldername(name))[1])::uuid, 'settings', 'edit'));
