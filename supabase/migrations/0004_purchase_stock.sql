-- =====================================================================
-- EZ ERP  |  0004  Purchase and stock (Phase 1, step 1D, part 1)
--
--   * trade_documents / trade_document_lines : one header and line table
--     shared by purchase documents (this migration) and sales documents
--     (0005). Totals are always computed on the server.
--   * Purchase workflow: requisition -> purchase order -> goods receipt
--     -> supplier bill, with approval steps and three-way matching.
--   * Stock ledger: immutable movements, per-warehouse balances valued at
--     weighted average cost, and approved stock adjustments.
--   * Accounting: goods receipts post Dr Inventory / Cr Goods received not
--     billed. Bills clear that account, book input tax and credit Accounts
--     payable. Adjustments post against Stock adjustments.
--
-- Payments, receipts and the receivable and payable aging reports are
-- part 2 (0005), together with sales.
-- =====================================================================

-- ---------------------------------------------------------------------
-- System accounts used by purchase and stock postings
-- ---------------------------------------------------------------------
create or replace function public.seed_trade_defaults(p_org uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform set_config('app.skip_audit', 'on', true);
  if not exists (select 1 from accounts where org_id = p_org and system_key = 'grni') then
    perform _seed_account(p_org, '2150', 'Goods received not billed', 'liability', '2000', false, 'grni');
  end if;
  if not exists (select 1 from accounts where org_id = p_org and system_key = 'purchase_variance') then
    perform _seed_account(p_org, '5150', 'Purchase price variance', 'expense', '5000', false, 'purchase_variance');
  end if;
  if not exists (select 1 from accounts where org_id = p_org and system_key = 'inventory_adjustment') then
    perform _seed_account(p_org, '5200', 'Stock adjustments and write-offs', 'expense', '5000', false, 'inventory_adjustment');
  end if;
  perform set_config('app.skip_audit', 'off', true);
end $$;

create or replace function public.trg_seed_org_trade()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.seed_trade_defaults(new.id);
  return new;
end $$;

-- Named so it fires after trg_seed_org_finance (accounts must exist first).
create trigger trg_seed_org_trade after insert on public.organizations
  for each row execute function public.trg_seed_org_trade();

-- ---------------------------------------------------------------------
-- Trade documents
-- ---------------------------------------------------------------------
create table public.trade_documents (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  doc_type text not null check (doc_type in (
    'purchase_requisition', 'purchase_order', 'goods_receipt', 'supplier_bill',
    'sales_quotation', 'sales_order', 'sales_invoice')),
  number text not null,
  doc_date date not null default current_date,
  due_date date,
  expected_date date,
  status text not null default 'draft' check (status in (
    'draft', 'pending', 'approved', 'rejected', 'ordered', 'partial', 'received', 'closed',
    'posted', 'sent', 'accepted', 'converted', 'expired', 'invoiced', 'cancelled')),
  party_id uuid references public.parties(id) on delete restrict,
  branch_id uuid references public.branches(id) on delete set null,
  warehouse_id uuid references public.warehouses(id) on delete restrict,
  department_id uuid references public.departments(id) on delete set null,
  source_id uuid references public.trade_documents(id) on delete restrict,
  reference text,
  notes text,
  subtotal numeric(18,2) not null default 0,
  discount_total numeric(18,2) not null default 0,
  tax_total numeric(18,2) not null default 0,
  total numeric(18,2) not null default 0,
  voucher_id uuid references public.vouchers(id) on delete set null,
  rejection_reason text,
  cancel_reason text,
  created_by uuid references public.profiles(id) on delete set null,
  submitted_at timestamptz,
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  posted_by uuid references public.profiles(id) on delete set null,
  posted_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, number)
);
create index trade_documents_list_idx on public.trade_documents(org_id, doc_type, doc_date desc);
create index trade_documents_party_idx on public.trade_documents(party_id);
create index trade_documents_source_idx on public.trade_documents(source_id);
create index trade_documents_status_idx on public.trade_documents(org_id, doc_type, status);
-- A supplier's own invoice number can be entered only once per supplier.
create unique index trade_bill_reference_unique on public.trade_documents (org_id, party_id, lower(btrim(reference)))
  where doc_type = 'supplier_bill' and status <> 'cancelled' and reference is not null and btrim(reference) <> '';
create trigger trade_documents_updated before update on public.trade_documents
  for each row execute function public.set_updated_at();

create table public.trade_document_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null references public.trade_documents(id) on delete cascade,
  line_no int not null,
  product_id uuid references public.products(id) on delete restrict,
  description text,
  quantity numeric(18,3) not null check (quantity > 0),
  unit_price numeric(18,4) not null default 0 check (unit_price >= 0),
  discount_amount numeric(18,2) not null default 0 check (discount_amount >= 0),
  tax_rate_id uuid references public.tax_rates(id) on delete set null,
  tax_rate numeric(7,3) not null default 0,
  tax_amount numeric(18,2) not null default 0,
  net_amount numeric(18,2) not null default 0,
  line_total numeric(18,2) not null default 0,
  account_id uuid references public.accounts(id) on delete restrict,
  source_line_id uuid references public.trade_document_lines(id) on delete restrict,
  check (product_id is not null or coalesce(btrim(description), '') <> ''),
  unique (document_id, line_no)
);
create index trade_lines_document_idx on public.trade_document_lines(document_id);
create index trade_lines_source_idx on public.trade_document_lines(source_line_id);
create index trade_lines_product_idx on public.trade_document_lines(product_id);

-- Posted and cancelled documents are history. A posted document can only move to cancelled.
create or replace function public.trade_documents_guard()
returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    if old.status not in ('draft', 'rejected') then
      raise exception 'Only draft or rejected documents can be deleted';
    end if;
    return old;
  end if;
  if old.status = 'cancelled' then
    raise exception 'A cancelled document cannot be changed';
  end if;
  if old.status = 'posted' then
    if new.status <> 'cancelled'
       or (to_jsonb(new) - 'status' - 'cancelled_at' - 'cancel_reason' - 'updated_at')
          is distinct from (to_jsonb(old) - 'status' - 'cancelled_at' - 'cancel_reason' - 'updated_at') then
      raise exception 'A posted document cannot be changed. Cancel it to reverse its effect.';
    end if;
  end if;
  return new;
end $$;
create trigger trade_documents_guard before update or delete on public.trade_documents
  for each row execute function public.trade_documents_guard();

-- Lines can only change while the document is a draft or was rejected.
create or replace function public.trade_lines_guard()
returns trigger language plpgsql as $$
declare v_status text; v_doc uuid := coalesce(new.document_id, old.document_id);
begin
  select status into v_status from trade_documents where id = v_doc;
  if found and v_status not in ('draft', 'rejected') then
    raise exception 'Lines cannot be changed once a document has been submitted';
  end if;
  return coalesce(new, old);
end $$;
create trigger trade_lines_guard before insert or update or delete on public.trade_document_lines
  for each row execute function public.trade_lines_guard();

-- ---------------------------------------------------------------------
-- Stock ledger, balances and adjustments
-- ---------------------------------------------------------------------
create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  movement_date date not null,
  movement_type text not null check (movement_type in (
    'purchase_receipt', 'purchase_return', 'sales_issue', 'sales_return',
    'adjustment_in', 'adjustment_out', 'transfer_in', 'transfer_out', 'reversal')),
  quantity numeric(18,3) not null check (quantity <> 0),
  unit_cost numeric(18,4) not null default 0,
  value numeric(18,2) not null default 0,
  source_type text,
  source_id uuid,
  source_line_id uuid,
  reference text,
  narration text,
  reversal_of uuid references public.stock_movements(id) on delete restrict,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index stock_movements_product_idx on public.stock_movements(org_id, product_id, movement_date desc, created_at desc);
create index stock_movements_source_idx on public.stock_movements(source_type, source_id);
create index stock_movements_warehouse_idx on public.stock_movements(warehouse_id);

create or replace function public.stock_movements_immutable()
returns trigger language plpgsql as $$
begin
  raise exception 'Stock movements cannot be changed. Post a reversal or an adjustment instead.';
end $$;
create trigger stock_movements_immutable before update or delete on public.stock_movements
  for each row execute function public.stock_movements_immutable();

-- Running balance per product and warehouse. Written only by _stock_move.
create table public.stock_balances (
  org_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  quantity numeric(18,3) not null default 0 check (quantity >= 0),
  avg_cost numeric(18,4) not null default 0,
  value numeric(18,2) not null default 0 check (value >= 0),
  updated_at timestamptz not null default now(),
  primary key (product_id, warehouse_id)
);
create index stock_balances_org_idx on public.stock_balances(org_id);

create table public.stock_adjustments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  number text not null,
  adj_date date not null default current_date,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  reason text not null check (reason in (
    'opening_stock', 'count_correction', 'damaged', 'expired', 'lost', 'issue', 'other')),
  status text not null default 'draft'
    check (status in ('draft', 'pending', 'approved', 'rejected', 'posted', 'cancelled')),
  notes text,
  voucher_id uuid references public.vouchers(id) on delete set null,
  rejection_reason text,
  cancel_reason text,
  created_by uuid references public.profiles(id) on delete set null,
  submitted_at timestamptz,
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  posted_by uuid references public.profiles(id) on delete set null,
  posted_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, number)
);
create index stock_adjustments_list_idx on public.stock_adjustments(org_id, adj_date desc);
create trigger stock_adjustments_updated before update on public.stock_adjustments
  for each row execute function public.set_updated_at();

create table public.stock_adjustment_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  adjustment_id uuid not null references public.stock_adjustments(id) on delete cascade,
  line_no int not null,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity_change numeric(18,3) not null check (quantity_change <> 0),
  unit_cost numeric(18,4) check (unit_cost is null or unit_cost >= 0),
  note text,
  unique (adjustment_id, line_no)
);
create index stock_adjustment_lines_idx on public.stock_adjustment_lines(adjustment_id);

create or replace function public.stock_adjustments_guard()
returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    if old.status not in ('draft', 'rejected') then
      raise exception 'Only draft or rejected adjustments can be deleted';
    end if;
    return old;
  end if;
  if old.status = 'cancelled' then raise exception 'A cancelled adjustment cannot be changed'; end if;
  if old.status = 'posted' then
    if new.status <> 'cancelled'
       or (to_jsonb(new) - 'status' - 'cancelled_at' - 'cancel_reason' - 'updated_at')
          is distinct from (to_jsonb(old) - 'status' - 'cancelled_at' - 'cancel_reason' - 'updated_at') then
      raise exception 'A posted adjustment cannot be changed. Cancel it to reverse its effect.';
    end if;
  end if;
  return new;
end $$;
create trigger stock_adjustments_guard before update or delete on public.stock_adjustments
  for each row execute function public.stock_adjustments_guard();

create or replace function public.stock_adjustment_lines_guard()
returns trigger language plpgsql as $$
declare v_status text; v_doc uuid := coalesce(new.adjustment_id, old.adjustment_id);
begin
  select status into v_status from stock_adjustments where id = v_doc;
  if found and v_status not in ('draft', 'rejected') then
    raise exception 'Lines cannot be changed once an adjustment has been submitted';
  end if;
  return coalesce(new, old);
end $$;
create trigger stock_adjustment_lines_guard before insert or update or delete on public.stock_adjustment_lines
  for each row execute function public.stock_adjustment_lines_guard();

-- ---------------------------------------------------------------------
-- Row level security. Reads are filtered here; every write goes through
-- the functions below, so no insert, update or delete policies exist.
-- ---------------------------------------------------------------------
alter table public.trade_documents enable row level security;
alter table public.trade_document_lines enable row level security;
alter table public.stock_movements enable row level security;
alter table public.stock_balances enable row level security;
alter table public.stock_adjustments enable row level security;
alter table public.stock_adjustment_lines enable row level security;

create policy trade_documents_select on public.trade_documents for select to authenticated using (
  case doc_type
    when 'purchase_requisition' then
      public.has_permission(org_id, 'requisitions', 'view')
      and (created_by = auth.uid()
           or public.has_permission(org_id, 'requisitions', 'approve')
           or public.has_permission(org_id, 'purchase', 'view'))
    when 'purchase_order' then public.has_permission(org_id, 'purchase', 'view')
    when 'goods_receipt' then
      public.has_permission(org_id, 'purchase', 'view') or public.has_permission(org_id, 'inventory', 'view')
    when 'supplier_bill' then
      public.has_permission(org_id, 'purchase', 'view') or public.has_permission(org_id, 'finance', 'view')
    else public.has_permission(org_id, 'sales', 'view')
  end);

create policy trade_lines_select on public.trade_document_lines for select to authenticated using (
  exists (select 1 from public.trade_documents d where d.id = document_id));

-- Cost figures are financial data: direct reads need both permissions.
-- Screens use the stock_* functions, which show quantities to everyone
-- with stock access and hide values from roles without financial data.
create policy stock_movements_select on public.stock_movements for select to authenticated using (
  public.has_permission(org_id, 'inventory', 'view') and public.has_permission(org_id, 'financial_data', 'view'));
create policy stock_balances_select on public.stock_balances for select to authenticated using (
  public.has_permission(org_id, 'inventory', 'view') and public.has_permission(org_id, 'financial_data', 'view'));

create policy stock_adjustments_select on public.stock_adjustments for select to authenticated using (
  public.has_permission(org_id, 'inventory', 'view'));
create policy stock_adjustment_lines_select on public.stock_adjustment_lines for select to authenticated using (
  exists (select 1 from public.stock_adjustments a where a.id = adjustment_id));

-- Attachments follow the permission of the record they belong to.
create or replace function public.can_view_attachment(p_org uuid, p_entity_type text)
returns boolean language sql stable security definer set search_path = public as $$
  select case p_entity_type
    when 'voucher' then public.has_permission(p_org, 'finance', 'view')
    when 'expense' then public.has_permission(p_org, 'expenses', 'view')
    when 'income' then public.has_permission(p_org, 'finance', 'view')
    when 'purchase_requisition' then public.has_permission(p_org, 'requisitions', 'view')
    when 'purchase_order' then public.has_permission(p_org, 'purchase', 'view')
    when 'goods_receipt' then public.has_permission(p_org, 'purchase', 'view') or public.has_permission(p_org, 'inventory', 'view')
    when 'supplier_bill' then public.has_permission(p_org, 'purchase', 'view') or public.has_permission(p_org, 'finance', 'view')
    when 'stock_adjustment' then public.has_permission(p_org, 'inventory', 'view')
    when 'sales_quotation' then public.has_permission(p_org, 'sales', 'view')
    when 'sales_order' then public.has_permission(p_org, 'sales', 'view')
    when 'sales_invoice' then public.has_permission(p_org, 'sales', 'view')
    else public.is_org_member(p_org)
  end;
$$;

select public.enable_audit('public.trade_documents');
select public.enable_audit('public.stock_adjustments');

-- ---------------------------------------------------------------------
-- Internal helpers (not callable from the app)
-- ---------------------------------------------------------------------
create or replace function public._sys_account(p_org uuid, p_key text)
returns uuid language plpgsql stable security definer set search_path = public as $$
declare v_id uuid;
begin
  select id into v_id from accounts where org_id = p_org and system_key = p_key;
  if v_id is null then raise exception 'The system account "%" is missing from the chart of accounts', p_key; end if;
  return v_id;
end $$;

-- Which permission a document type is governed by.
create or replace function public._doc_can(p_org uuid, p_type text, p_action text)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_type = 'purchase_requisition' then public.has_permission(p_org, 'requisitions', p_action)
    when p_type = 'goods_receipt' then
      case when p_action = 'approve'
        then public.has_permission(p_org, 'inventory', 'edit') or public.has_permission(p_org, 'purchase', 'approve')
        else public.has_permission(p_org, 'inventory', p_action) or public.has_permission(p_org, 'purchase', p_action)
      end
    when p_type in ('purchase_order', 'supplier_bill') then public.has_permission(p_org, 'purchase', p_action)
    else public.has_permission(p_org, 'sales', p_action)
  end;
$$;

create or replace function public._doc_label(p_type text)
returns text language sql immutable as $$
  select case p_type
    when 'purchase_requisition' then 'Purchase requisition'
    when 'purchase_order' then 'Purchase order'
    when 'goods_receipt' then 'Goods receipt'
    when 'supplier_bill' then 'Supplier bill'
    when 'sales_quotation' then 'Quotation'
    when 'sales_order' then 'Sales order'
    when 'sales_invoice' then 'Sales invoice'
    else p_type
  end;
$$;

-- ---------------------------------------------------------------------
-- Stock engine. Every quantity change in the system goes through here.
-- Costing is weighted average per product and warehouse.
-- Returns the signed value of the movement (positive in, negative out).
-- ---------------------------------------------------------------------
create or replace function public._stock_move(
  p_org uuid, p_product uuid, p_wh uuid, p_date date, p_type text, p_qty numeric,
  p_unit_cost numeric, p_source_type text, p_source_id uuid, p_source_line uuid,
  p_ref text, p_narration text, p_reversal_of uuid default null
) returns numeric language plpgsql security definer set search_path = public as $$
declare
  b stock_balances%rowtype;
  v_cost numeric; v_val numeric; v_qty numeric; v_new_val numeric; v_avg numeric;
  v_name text; v_wh text;
begin
  if p_qty is null or p_qty = 0 then raise exception 'A stock movement needs a quantity'; end if;
  if not exists (select 1 from products where id = p_product and org_id = p_org) then
    raise exception 'Item not found';
  end if;
  if not exists (select 1 from warehouses where id = p_wh and org_id = p_org) then
    raise exception 'Warehouse not found';
  end if;

  insert into stock_balances (org_id, product_id, warehouse_id) values (p_org, p_product, p_wh)
  on conflict (product_id, warehouse_id) do nothing;
  select * into b from stock_balances where product_id = p_product and warehouse_id = p_wh for update;

  v_qty := b.quantity + p_qty;
  if p_qty > 0 then
    v_cost := coalesce(p_unit_cost, b.avg_cost);
    v_val := round(p_qty * v_cost, 2);
    v_new_val := b.value + v_val;
    v_avg := case when v_qty > 0 then round(v_new_val / v_qty, 4) else b.avg_cost end;
  else
    if v_qty < 0 then
      select name into v_name from products where id = p_product;
      select name into v_wh from warehouses where id = p_wh;
      raise exception 'Not enough stock of % in %. Available: %, needed: %', v_name, v_wh, trim_scale(b.quantity), trim_scale(abs(p_qty));
    end if;
    if p_unit_cost is null then
      v_cost := b.avg_cost;
      v_val := case when v_qty = 0 then -b.value else -round(abs(p_qty) * v_cost, 2) end;
    else
      -- Reversals leave at the cost they came in at.
      v_cost := p_unit_cost;
      v_val := -round(abs(p_qty) * v_cost, 2);
    end if;
    v_new_val := b.value + v_val;
    if v_new_val < 0 or (v_qty = 0 and v_new_val <> 0) then
      raise exception 'Part of this stock has already been used, so the movement cannot be reversed. Post a stock adjustment instead.';
    end if;
    v_avg := case when v_qty > 0 then round(v_new_val / v_qty, 4) else b.avg_cost end;
  end if;

  update stock_balances set quantity = v_qty, value = v_new_val, avg_cost = v_avg, updated_at = now()
  where product_id = p_product and warehouse_id = p_wh;

  insert into stock_movements (org_id, product_id, warehouse_id, movement_date, movement_type, quantity,
                               unit_cost, value, source_type, source_id, source_line_id, reference,
                               narration, reversal_of, created_by)
  values (p_org, p_product, p_wh, p_date, p_type, p_qty, v_cost, v_val, p_source_type, p_source_id,
          p_source_line, p_ref, p_narration, p_reversal_of, auth.uid());
  return v_val;
end $$;

-- Keeps a requisition's status in step with the purchase orders raised from it.
create or replace function public._sync_requisition(p_req uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  if p_req is null then return; end if;
  select status into v_status from trade_documents where id = p_req and doc_type = 'purchase_requisition';
  if v_status not in ('approved', 'ordered') then return; end if;
  update trade_documents set status = case when exists (
    select 1 from trade_documents po where po.source_id = p_req and po.doc_type = 'purchase_order' and po.status <> 'cancelled'
  ) then 'ordered' else 'approved' end
  where id = p_req;
end $$;

-- Recomputes an order's receiving status from its posted receipts.
create or replace function public._sync_po_status(p_po uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_status text; v_ordered numeric; v_received numeric; v_all_done boolean;
begin
  if p_po is null then return; end if;
  select status into v_status from trade_documents where id = p_po and doc_type = 'purchase_order';
  if v_status is null or v_status not in ('approved', 'partial', 'received') then return; end if;

  select coalesce(bool_and(rec.qty >= l.quantity), true), coalesce(sum(rec.qty), 0), count(*)
    into v_all_done, v_received, v_ordered
  from trade_document_lines l
  join products p on p.id = l.product_id and p.track_inventory and p.item_type <> 'service'
  cross join lateral (
    select coalesce(sum(g.quantity), 0) as qty
    from trade_document_lines g join trade_documents gd on gd.id = g.document_id
    where g.source_line_id = l.id and gd.doc_type = 'goods_receipt' and gd.status = 'posted'
  ) rec
  where l.document_id = p_po;

  update trade_documents set status = case
      when v_ordered = 0 then 'approved'
      when v_all_done then 'received'
      when v_received > 0 then 'partial'
      else 'approved' end
  where id = p_po;
end $$;

-- ---------------------------------------------------------------------
-- Save a purchase document (requisition, order, receipt or bill).
-- Quantities and prices come from the app; amounts, taxes and links are
-- checked and calculated here.
-- ---------------------------------------------------------------------
create or replace function public.save_purchase_document(
  p_id uuid, p_org uuid, p_type text, p_party uuid, p_date date, p_due date, p_expected date,
  p_branch uuid, p_warehouse uuid, p_department uuid, p_reference text, p_notes text,
  p_source uuid, p_lines jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  d trade_documents%rowtype;
  v_exists boolean := false;
  v_party parties%rowtype;
  r record;
  v_n int := 0;
  v_prod products%rowtype;
  v_rate tax_rates%rowtype;
  v_acct accounts%rowtype;
  v_src trade_document_lines%rowtype;
  v_srcdoc trade_documents%rowtype;
  v_stock boolean;
  v_qty numeric; v_price numeric; v_gross numeric; v_disc numeric; v_net numeric;
  v_tax numeric; v_trate numeric; v_tax_id uuid; v_account uuid; v_srcline uuid;
  v_remaining numeric;
  v_sub numeric := 0; v_dsum numeric := 0; v_tsum numeric := 0;
  v_due date; v_ref text := nullif(btrim(coalesce(p_reference, '')), '');
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  if not public.is_org_member(p_org) then raise exception 'Access denied'; end if;
  if p_type not in ('purchase_requisition', 'purchase_order', 'goods_receipt', 'supplier_bill') then
    raise exception 'Unsupported document type';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Add at least one line';
  end if;
  if p_date is null then raise exception 'Choose a date'; end if;

  select * into d from trade_documents where id = p_id;
  if found then
    v_exists := true;
    if d.org_id <> p_org or d.doc_type <> p_type then raise exception 'Document not found'; end if;
    if d.status not in ('draft', 'rejected') then raise exception 'Only draft or rejected documents can be edited'; end if;
    if not (public._doc_can(p_org, p_type, 'edit') or (d.created_by = v_uid and public._doc_can(p_org, p_type, 'create'))) then
      raise exception 'You do not have permission to edit this document';
    end if;
  elsif not public._doc_can(p_org, p_type, 'create') then
    raise exception 'You do not have permission to create this document';
  end if;

  -- Header checks
  if p_type <> 'purchase_requisition' and p_party is null then raise exception 'Choose a supplier'; end if;
  if p_party is not null then
    select * into v_party from parties where id = p_party and org_id = p_org;
    if not found or not v_party.is_supplier then raise exception 'Choose a valid supplier'; end if;
    if not v_party.is_active then raise exception 'This supplier is archived'; end if;
  end if;
  if p_type = 'goods_receipt' and p_warehouse is null then
    raise exception 'Choose the warehouse that is receiving the goods';
  end if;
  if p_warehouse is not null and not exists (
    select 1 from warehouses where id = p_warehouse and org_id = p_org and is_active) then
    raise exception 'Choose a valid warehouse';
  end if;
  if p_branch is not null and not exists (select 1 from branches where id = p_branch and org_id = p_org) then
    raise exception 'Choose a valid branch';
  end if;
  if p_department is not null and not exists (select 1 from departments where id = p_department and org_id = p_org) then
    raise exception 'Choose a valid department';
  end if;

  if p_source is not null then
    select * into v_srcdoc from trade_documents where id = p_source and org_id = p_org;
    if not found then raise exception 'The source document was not found'; end if;
    if p_type = 'purchase_order' then
      if v_srcdoc.doc_type <> 'purchase_requisition' or v_srcdoc.status not in ('approved', 'ordered') then
        raise exception 'Only an approved requisition can be converted to a purchase order';
      end if;
    elsif p_type = 'goods_receipt' then
      if v_srcdoc.doc_type <> 'purchase_order' or v_srcdoc.status not in ('approved', 'partial') then
        raise exception 'Goods can only be received against an approved purchase order that is still open';
      end if;
      if v_srcdoc.party_id is distinct from p_party then
        raise exception 'The supplier must match the purchase order';
      end if;
    else
      raise exception 'This document cannot be created from another document';
    end if;
  end if;

  if p_type = 'supplier_bill' and v_ref is not null and exists (
    select 1 from trade_documents
    where org_id = p_org and doc_type = 'supplier_bill' and party_id = p_party and status <> 'cancelled'
      and lower(btrim(reference)) = lower(v_ref) and id <> p_id) then
    raise exception 'A bill with the supplier invoice number "%" already exists for this supplier', v_ref;
  end if;

  v_due := case p_type
    when 'supplier_bill' then coalesce(p_due, p_date + coalesce(v_party.payment_terms_days, 0))
    else null end;

  -- Header
  if not v_exists then
    insert into trade_documents (id, org_id, doc_type, number, doc_date, due_date, expected_date, status,
                                 party_id, branch_id, warehouse_id, department_id, source_id, reference,
                                 notes, created_by)
    values (p_id, p_org, p_type, public.next_doc_number(p_org, p_type), p_date, v_due, p_expected, 'draft',
            p_party, p_branch, p_warehouse, p_department, p_source, v_ref,
            nullif(btrim(coalesce(p_notes, '')), ''), v_uid);
  else
    update trade_documents set
      doc_date = p_date, due_date = v_due, expected_date = p_expected, status = 'draft',
      party_id = p_party, branch_id = p_branch, warehouse_id = p_warehouse, department_id = p_department,
      source_id = p_source, reference = v_ref, notes = nullif(btrim(coalesce(p_notes, '')), ''),
      rejection_reason = null
    where id = p_id;
    delete from trade_document_lines where document_id = p_id;
  end if;

  -- Lines
  for r in
    select * from jsonb_to_recordset(p_lines) as x(
      product_id uuid, description text, quantity numeric, unit_price numeric, discount_amount numeric,
      tax_rate_id uuid, account_id uuid, source_line_id uuid)
  loop
    v_n := v_n + 1;
    v_qty := round(coalesce(r.quantity, 0), 3);
    if v_qty <= 0 then raise exception 'Line %: enter a quantity greater than zero', v_n; end if;

    v_prod := null;
    if r.product_id is not null then
      select * into v_prod from products where id = r.product_id and org_id = p_org;
      if not found then raise exception 'Line %: the item was not found', v_n; end if;
      if not v_prod.is_active then raise exception 'Line %: "%" is archived', v_n, v_prod.name; end if;
    elsif btrim(coalesce(r.description, '')) = '' then
      raise exception 'Line %: choose an item or write a description', v_n;
    end if;
    v_stock := v_prod.id is not null and v_prod.track_inventory and v_prod.item_type <> 'service';

    v_price := round(coalesce(r.unit_price, 0), 4);
    if v_price < 0 then raise exception 'Line %: the price cannot be negative', v_n; end if;
    v_gross := round(v_qty * v_price, 2);
    v_disc := case when p_type in ('purchase_order', 'supplier_bill') then round(coalesce(r.discount_amount, 0), 2) else 0 end;
    if v_disc < 0 or v_disc > v_gross then raise exception 'Line %: the discount cannot exceed the line amount', v_n; end if;
    v_net := v_gross - v_disc;

    v_tax := 0; v_trate := 0; v_tax_id := null;
    if r.tax_rate_id is not null and p_type in ('purchase_order', 'supplier_bill') then
      select * into v_rate from tax_rates
      where id = r.tax_rate_id and org_id = p_org and is_active and applies_to in ('purchase', 'both');
      if not found then raise exception 'Line %: choose a valid tax rate', v_n; end if;
      v_tax_id := v_rate.id; v_trate := v_rate.rate; v_tax := round(v_net * v_trate / 100, 2);
    end if;

    v_account := null; v_srcline := null;

    if p_type = 'goods_receipt' then
      if not v_stock then
        raise exception 'Line %: only stock items can be received. Bill services and non-stock items directly.', v_n;
      end if;
      if p_source is not null and r.source_line_id is null then
        raise exception 'Line %: every line must come from the purchase order', v_n;
      end if;
      if r.source_line_id is not null then
        select * into v_src from trade_document_lines where id = r.source_line_id;
        if not found or v_src.document_id is distinct from p_source then
          raise exception 'Line %: this line does not belong to the selected purchase order', v_n;
        end if;
        if v_src.product_id is distinct from r.product_id then
          raise exception 'Line %: the item differs from the order line', v_n;
        end if;
        select v_src.quantity - coalesce(sum(g.quantity), 0) into v_remaining
        from trade_document_lines g join trade_documents gd on gd.id = g.document_id
        where g.source_line_id = v_src.id and gd.doc_type = 'goods_receipt' and gd.status = 'posted' and gd.id <> p_id;
        if v_qty > v_remaining then
          raise exception 'Line %: only % remain to be received on this order', v_n, trim_scale(v_remaining);
        end if;
        v_srcline := v_src.id;
      end if;

    elsif p_type = 'supplier_bill' then
      if v_stock then
        if r.source_line_id is null then
          raise exception 'Line %: stock items are billed from a goods receipt. Receive the goods first.', v_n;
        end if;
        select * into v_src from trade_document_lines where id = r.source_line_id;
        select * into v_srcdoc from trade_documents where id = v_src.document_id;
        if not found or v_srcdoc.org_id <> p_org or v_srcdoc.doc_type <> 'goods_receipt' or v_srcdoc.status <> 'posted'
           or v_srcdoc.party_id is distinct from p_party then
          raise exception 'Line %: choose a posted goods receipt from the same supplier', v_n;
        end if;
        if v_src.product_id is distinct from r.product_id then
          raise exception 'Line %: the item differs from the receipt line', v_n;
        end if;
        select v_src.quantity - coalesce(sum(b.quantity), 0) into v_remaining
        from trade_document_lines b join trade_documents bd on bd.id = b.document_id
        where b.source_line_id = v_src.id and bd.doc_type = 'supplier_bill' and bd.status <> 'cancelled' and bd.id <> p_id;
        if v_qty > v_remaining then
          raise exception 'Line %: only % remain to be billed on this receipt', v_n, trim_scale(v_remaining);
        end if;
        v_srcline := v_src.id;
      else
        if r.account_id is null then
          raise exception 'Line %: choose the expense account for this line', v_n;
        end if;
        select * into v_acct from accounts where id = r.account_id and org_id = p_org;
        if not found or v_acct.is_group or not v_acct.is_active or v_acct.account_type not in ('expense', 'asset') then
          raise exception 'Line %: choose an active expense or asset account', v_n;
        end if;
        v_account := v_acct.id;
        if r.source_line_id is not null then
          select * into v_src from trade_document_lines where id = r.source_line_id;
          select * into v_srcdoc from trade_documents where id = v_src.document_id;
          if not found or v_srcdoc.org_id <> p_org or v_srcdoc.doc_type <> 'purchase_order'
             or v_srcdoc.status not in ('approved', 'partial', 'received', 'closed')
             or v_srcdoc.party_id is distinct from p_party then
            raise exception 'Line %: choose a line from an approved order of the same supplier', v_n;
          end if;
          if v_src.product_id is distinct from r.product_id then
            raise exception 'Line %: the item differs from the order line', v_n;
          end if;
          select v_src.quantity - coalesce(sum(b.quantity), 0) into v_remaining
          from trade_document_lines b join trade_documents bd on bd.id = b.document_id
          where b.source_line_id = v_src.id and bd.doc_type = 'supplier_bill' and bd.status <> 'cancelled' and bd.id <> p_id;
          if v_qty > v_remaining then
            raise exception 'Line %: only % remain to be billed on this order line', v_n, trim_scale(v_remaining);
          end if;
          v_srcline := v_src.id;
        end if;
      end if;

    elsif p_type = 'purchase_order' and r.source_line_id is not null then
      select * into v_src from trade_document_lines where id = r.source_line_id;
      if found and v_src.document_id is not distinct from p_source then v_srcline := v_src.id; end if;
    end if;

    insert into trade_document_lines (org_id, document_id, line_no, product_id, description, quantity,
                                      unit_price, discount_amount, tax_rate_id, tax_rate, tax_amount,
                                      net_amount, line_total, account_id, source_line_id)
    values (p_org, p_id, v_n, r.product_id, nullif(btrim(coalesce(r.description, '')), ''), v_qty,
            v_price, v_disc, v_tax_id, v_trate, v_tax, v_net, v_net + v_tax, v_account, v_srcline);

    v_sub := v_sub + v_gross; v_dsum := v_dsum + v_disc; v_tsum := v_tsum + v_tax;
  end loop;

  update trade_documents
  set subtotal = v_sub, discount_total = v_dsum, tax_total = v_tsum, total = v_sub - v_dsum + v_tsum
  where id = p_id;

  if p_type = 'purchase_order' then perform public._sync_requisition(p_source); end if;
  return p_id;
end $$;

-- ---------------------------------------------------------------------
-- Approval workflow shared by requisitions, orders and bills
-- ---------------------------------------------------------------------
create or replace function public.submit_document(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d trade_documents%rowtype; v_uid uuid := auth.uid(); v_module text;
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) then raise exception 'Document not found'; end if;
  if d.doc_type not in ('purchase_requisition', 'purchase_order', 'supplier_bill') then
    raise exception 'This document is not submitted for approval';
  end if;
  if d.status not in ('draft', 'rejected') then raise exception 'Only draft or rejected documents can be submitted'; end if;
  if not (public._doc_can(d.org_id, d.doc_type, 'edit') or (d.created_by = v_uid and public._doc_can(d.org_id, d.doc_type, 'create'))) then
    raise exception 'You do not have permission to submit this document';
  end if;
  if not exists (select 1 from trade_document_lines where document_id = p_id) then
    raise exception 'Add at least one line before submitting';
  end if;

  update trade_documents set status = 'pending', submitted_at = now(), rejection_reason = null where id = p_id;
  v_module := case when d.doc_type = 'purchase_requisition' then 'requisitions' else 'purchase' end;
  perform public.notify_members_with_permission(
    d.org_id, v_module, 'approve',
    public._doc_label(d.doc_type) || ' ' || d.number || ' needs approval',
    case when d.doc_type = 'purchase_requisition' then 'A requisition is waiting for your decision.'
         else 'Total ' || to_char(d.total, 'FM999,999,999,990.00') end,
    'approval', d.doc_type, d.id);
end $$;

create or replace function public.approve_document(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d trade_documents%rowtype;
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) then raise exception 'Document not found'; end if;
  if d.doc_type not in ('purchase_requisition', 'purchase_order', 'supplier_bill') then
    raise exception 'This document is not approved here';
  end if;
  if d.status <> 'pending' then raise exception 'Only pending documents can be approved'; end if;
  if not public._doc_can(d.org_id, d.doc_type, 'approve') then
    raise exception 'You do not have permission to approve this document';
  end if;

  update trade_documents set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_id;
  perform public._notify_user(d.org_id, d.created_by,
    public._doc_label(d.doc_type) || ' ' || d.number || ' approved', null, 'approval', d.doc_type, d.id);
  if d.doc_type = 'purchase_requisition' then
    perform public.notify_members_with_permission(
      d.org_id, 'purchase', 'create', 'Requisition ' || d.number || ' is approved',
      'It is ready to be converted to a purchase order.', 'info', d.doc_type, d.id);
  end if;
end $$;

create or replace function public.reject_document(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare d trade_documents%rowtype;
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) then raise exception 'Document not found'; end if;
  if d.doc_type not in ('purchase_requisition', 'purchase_order', 'supplier_bill') then
    raise exception 'This document is not approved here';
  end if;
  if d.status <> 'pending' then raise exception 'Only pending documents can be rejected'; end if;
  if not public._doc_can(d.org_id, d.doc_type, 'approve') then
    raise exception 'You do not have permission to reject this document';
  end if;
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'Give a reason for the rejection'; end if;

  update trade_documents set status = 'rejected', rejection_reason = btrim(p_reason) where id = p_id;
  perform public._notify_user(d.org_id, d.created_by,
    public._doc_label(d.doc_type) || ' ' || d.number || ' was rejected', btrim(p_reason), 'approval', d.doc_type, d.id);
  if d.doc_type = 'purchase_order' then perform public._sync_requisition(d.source_id); end if;
end $$;

create or replace function public.discard_document(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d trade_documents%rowtype; v_uid uuid := auth.uid();
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) then raise exception 'Document not found'; end if;
  if d.status not in ('draft', 'rejected') then raise exception 'Only draft or rejected documents can be deleted'; end if;
  if not (public._doc_can(d.org_id, d.doc_type, 'delete')
          or (d.created_by = v_uid and public._doc_can(d.org_id, d.doc_type, 'create'))) then
    raise exception 'You do not have permission to delete this document';
  end if;
  delete from attachments where org_id = d.org_id and entity_type = d.doc_type and entity_id = p_id;
  delete from trade_documents where id = p_id;
  if d.doc_type = 'purchase_order' then perform public._sync_requisition(d.source_id); end if;
end $$;

-- Cancels a document. Posted receipts and bills are reversed, not erased.
create or replace function public.cancel_document(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  d trade_documents%rowtype; v_uid uuid := auth.uid(); v_reason text := btrim(coalesce(p_reason, ''));
  m stock_movements%rowtype;
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) then raise exception 'Document not found'; end if;
  if v_reason = '' then raise exception 'Give a reason for cancelling'; end if;
  if d.status = 'cancelled' then raise exception 'This document is already cancelled'; end if;

  if d.doc_type = 'purchase_requisition' then
    if d.status = 'ordered' then raise exception 'A purchase order has been raised from this requisition. Cancel that order first.'; end if;
    if d.status not in ('draft', 'pending', 'approved', 'rejected') then raise exception 'This requisition cannot be cancelled'; end if;
    if not (public._doc_can(d.org_id, d.doc_type, 'approve') or d.created_by = v_uid) then
      raise exception 'You do not have permission to cancel this requisition';
    end if;

  elsif d.doc_type = 'purchase_order' then
    if d.status in ('partial', 'received', 'closed') then
      raise exception 'Goods have been received on this order. Close it instead of cancelling.';
    end if;
    if d.status not in ('draft', 'pending', 'approved', 'rejected') then raise exception 'This order cannot be cancelled'; end if;
    if not (public._doc_can(d.org_id, d.doc_type, 'approve') or (d.created_by = v_uid and d.status in ('draft', 'rejected'))) then
      raise exception 'You do not have permission to cancel this order';
    end if;
    if exists (
      select 1 from trade_document_lines c join trade_documents cd on cd.id = c.document_id
      where cd.status <> 'cancelled' and c.source_line_id in (select id from trade_document_lines where document_id = p_id)
    ) or exists (select 1 from trade_documents x where x.source_id = p_id and x.status <> 'cancelled') then
      raise exception 'This order already has receipts or bills. Cancel those first.';
    end if;

  elsif d.doc_type = 'goods_receipt' then
    if d.status = 'draft' then
      if not (public._doc_can(d.org_id, d.doc_type, 'approve') or d.created_by = v_uid) then
        raise exception 'You do not have permission to cancel this receipt';
      end if;
    elsif d.status = 'posted' then
      if not public._doc_can(d.org_id, d.doc_type, 'approve') then
        raise exception 'You do not have permission to cancel a posted receipt';
      end if;
      if exists (
        select 1 from trade_document_lines b join trade_documents bd on bd.id = b.document_id
        where bd.status <> 'cancelled' and bd.doc_type = 'supplier_bill'
          and b.source_line_id in (select id from trade_document_lines where document_id = p_id)
      ) then
        raise exception 'This receipt has been billed. Cancel the bill first.';
      end if;
      for m in select * from stock_movements where source_type = 'goods_receipt' and source_id = p_id and reversal_of is null loop
        perform public._stock_move(d.org_id, m.product_id, m.warehouse_id, current_date, 'reversal', -m.quantity,
          m.unit_cost, 'goods_receipt', p_id, m.source_line_id, d.number, 'Reversal of ' || d.number, m.id);
      end loop;
      if d.voucher_id is not null then perform public._reverse_voucher(d.voucher_id, current_date, v_reason); end if;
    else
      raise exception 'This receipt cannot be cancelled';
    end if;

  elsif d.doc_type = 'supplier_bill' then
    if d.status = 'posted' then
      if not public._doc_can(d.org_id, d.doc_type, 'approve') then
        raise exception 'You do not have permission to cancel a posted bill';
      end if;
      if d.voucher_id is not null then perform public._reverse_voucher(d.voucher_id, current_date, v_reason); end if;
    elsif d.status in ('draft', 'pending', 'approved', 'rejected') then
      if not (public._doc_can(d.org_id, d.doc_type, 'approve') or (d.created_by = v_uid and d.status in ('draft', 'rejected'))) then
        raise exception 'You do not have permission to cancel this bill';
      end if;
    else
      raise exception 'This bill cannot be cancelled';
    end if;
  else
    raise exception 'This document cannot be cancelled here';
  end if;

  update trade_documents set status = 'cancelled', cancel_reason = v_reason, cancelled_at = now() where id = p_id;
  if d.doc_type = 'purchase_order' then perform public._sync_requisition(d.source_id); end if;
  if d.doc_type = 'goods_receipt' then perform public._sync_po_status(d.source_id); end if;
  if d.created_by is not null and d.created_by <> v_uid then
    perform public._notify_user(d.org_id, d.created_by,
      public._doc_label(d.doc_type) || ' ' || d.number || ' was cancelled', v_reason, 'info', d.doc_type, d.id);
  end if;
end $$;

-- Stops further receiving on an order that will not be delivered in full.
create or replace function public.close_purchase_order(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare d trade_documents%rowtype;
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) or d.doc_type <> 'purchase_order' then raise exception 'Order not found'; end if;
  if not public._doc_can(d.org_id, d.doc_type, 'approve') then raise exception 'You do not have permission to close this order'; end if;
  if d.status not in ('approved', 'partial') then raise exception 'Only an open order can be closed'; end if;
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'Give a reason for closing the order'; end if;
  update trade_documents set status = 'closed', cancel_reason = btrim(p_reason) where id = p_id;
end $$;

-- ---------------------------------------------------------------------
-- Goods receipt: moves stock in and books Dr Inventory / Cr Goods received not billed
-- ---------------------------------------------------------------------
create or replace function public.post_goods_receipt(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  d trade_documents%rowtype; l record; v_total numeric := 0; v_val numeric; v_voucher uuid;
  v_inventory uuid; v_grni uuid; v_remaining numeric;
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) or d.doc_type <> 'goods_receipt' then raise exception 'Receipt not found'; end if;
  if d.status <> 'draft' then raise exception 'Only a draft receipt can be posted'; end if;
  if not public._doc_can(d.org_id, d.doc_type, 'approve') then raise exception 'You do not have permission to post receipts'; end if;
  if d.warehouse_id is null then raise exception 'Choose a warehouse'; end if;

  for l in select * from trade_document_lines where document_id = p_id order by line_no loop
    if l.source_line_id is not null then
      select q.quantity - coalesce(sum(g.quantity), 0) into v_remaining
      from trade_document_lines q
      left join trade_document_lines g on g.source_line_id = q.id and g.document_id <> p_id
        and exists (select 1 from trade_documents gd where gd.id = g.document_id and gd.doc_type = 'goods_receipt' and gd.status = 'posted')
      where q.id = l.source_line_id
      group by q.quantity;
      if l.quantity > v_remaining then
        raise exception 'Line %: only % remain to be received on the order', l.line_no, trim_scale(v_remaining);
      end if;
    end if;
    v_val := public._stock_move(d.org_id, l.product_id, d.warehouse_id, d.doc_date, 'purchase_receipt', l.quantity,
      l.unit_price, 'goods_receipt', d.id, l.id, d.number, null);
    v_total := v_total + v_val;
  end loop;

  if v_total > 0 then
    v_inventory := public._sys_account(d.org_id, 'inventory');
    v_grni := public._sys_account(d.org_id, 'grni');
    v_voucher := public._post_new_voucher(
      d.org_id, 'journal', d.doc_date, 'Goods received ' || d.number, d.reference, d.branch_id,
      jsonb_build_array(
        jsonb_build_object('account_id', v_inventory, 'debit', v_total, 'description', 'Stock received ' || d.number),
        jsonb_build_object('account_id', v_grni, 'credit', v_total, 'party_id', d.party_id, 'description', 'Goods received not billed')),
      'goods_receipt', d.id);
  end if;

  update trade_documents set status = 'posted', posted_by = auth.uid(), posted_at = now(), voucher_id = v_voucher
  where id = p_id;
  perform public._sync_po_status(d.source_id);
  perform public.notify_members_with_permission(
    d.org_id, 'purchase', 'create', 'Goods received: ' || d.number, 'Ready to be billed by the supplier invoice.',
    'info', 'goods_receipt', d.id);
end $$;

-- ---------------------------------------------------------------------
-- Supplier bill: clears Goods received not billed, books input tax and
-- credits Accounts payable. Approves the bill if it is not approved yet.
-- ---------------------------------------------------------------------
create or replace function public.post_supplier_bill(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  d trade_documents%rowtype; l record; g trade_document_lines%rowtype;
  v_grni_total numeric := 0; v_variance numeric := 0; v_grni numeric; v_voucher uuid;
  v_lines jsonb := '[]'::jsonb; a record; v_party text; v_billed numeric;
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) or d.doc_type <> 'supplier_bill' then raise exception 'Bill not found'; end if;
  if d.status not in ('draft', 'pending', 'approved') then raise exception 'This bill cannot be posted'; end if;
  if not public._doc_can(d.org_id, d.doc_type, 'approve') then raise exception 'You do not have permission to approve and post bills'; end if;
  if d.total <= 0 then raise exception 'The bill total must be greater than zero'; end if;
  select name into v_party from parties where id = d.party_id;

  for l in select * from trade_document_lines where document_id = p_id order by line_no loop
    if l.account_id is null then
      -- Stock line: matched against the receipt it was entered from.
      select * into g from trade_document_lines where id = l.source_line_id;
      select coalesce(sum(b.quantity), 0) into v_billed
      from trade_document_lines b join trade_documents bd on bd.id = b.document_id
      where b.source_line_id = g.id and bd.doc_type = 'supplier_bill' and bd.status <> 'cancelled';
      if v_billed > g.quantity then
        raise exception 'Line %: more has been billed than was received', l.line_no;
      end if;
      v_grni := round(l.quantity * g.unit_price, 2);
      v_grni_total := v_grni_total + v_grni;
      v_variance := v_variance + (l.net_amount - v_grni);
    end if;
  end loop;

  if v_grni_total > 0 then
    v_lines := v_lines || jsonb_build_object('account_id', public._sys_account(d.org_id, 'grni'),
      'debit', v_grni_total, 'party_id', d.party_id, 'description', 'Goods received now billed');
  end if;
  if v_variance > 0 then
    v_lines := v_lines || jsonb_build_object('account_id', public._sys_account(d.org_id, 'purchase_variance'),
      'debit', v_variance, 'description', 'Price difference against receipt cost');
  elsif v_variance < 0 then
    v_lines := v_lines || jsonb_build_object('account_id', public._sys_account(d.org_id, 'purchase_variance'),
      'credit', -v_variance, 'description', 'Price difference against receipt cost');
  end if;
  for a in
    select account_id, sum(net_amount) as amount from trade_document_lines
    where document_id = p_id and account_id is not null group by account_id having sum(net_amount) > 0
  loop
    v_lines := v_lines || jsonb_build_object('account_id', a.account_id, 'debit', a.amount, 'party_id', d.party_id,
      'description', 'Bill ' || d.number);
  end loop;
  if d.tax_total > 0 then
    v_lines := v_lines || jsonb_build_object('account_id', public._sys_account(d.org_id, 'input_tax'),
      'debit', d.tax_total, 'description', 'Input tax on ' || d.number);
  end if;
  v_lines := v_lines || jsonb_build_object('account_id', public._sys_account(d.org_id, 'accounts_payable'),
    'credit', d.total, 'party_id', d.party_id, 'description', 'Payable to ' || v_party);

  v_voucher := public._post_new_voucher(
    d.org_id, 'journal', d.doc_date, 'Supplier bill ' || d.number || ' - ' || v_party, d.reference, d.branch_id,
    v_lines, 'supplier_bill', d.id);

  update trade_documents set status = 'posted', posted_by = auth.uid(), posted_at = now(), voucher_id = v_voucher,
    approved_by = coalesce(approved_by, auth.uid()), approved_at = coalesce(approved_at, now())
  where id = p_id;

  perform public._notify_user(d.org_id, d.created_by, 'Bill ' || d.number || ' is posted', null, 'info', d.doc_type, d.id);
  perform public.notify_members_with_permission(
    d.org_id, 'finance', 'create', 'Bill ' || d.number || ' is due ' || to_char(d.due_date, 'DD Mon YYYY'),
    v_party || ' - total ' || to_char(d.total, 'FM999,999,999,990.00'), 'due', 'supplier_bill', d.id);
end $$;

-- ---------------------------------------------------------------------
-- Stock adjustments: opening stock, count corrections, damaged, expired,
-- lost and internal issues. Approved before they change stock.
-- ---------------------------------------------------------------------
create or replace function public.save_stock_adjustment(
  p_id uuid, p_org uuid, p_date date, p_warehouse uuid, p_reason text, p_notes text, p_lines jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); a stock_adjustments%rowtype; v_exists boolean := false;
  r record; v_n int := 0; v_prod products%rowtype; v_qty numeric;
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  if not public.is_org_member(p_org) then raise exception 'Access denied'; end if;
  if p_reason not in ('opening_stock', 'count_correction', 'damaged', 'expired', 'lost', 'issue', 'other') then
    raise exception 'Choose a reason';
  end if;
  if p_date is null then raise exception 'Choose a date'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Add at least one line';
  end if;
  if not exists (select 1 from warehouses where id = p_warehouse and org_id = p_org and is_active) then
    raise exception 'Choose a valid warehouse';
  end if;

  select * into a from stock_adjustments where id = p_id;
  if found then
    v_exists := true;
    if a.org_id <> p_org then raise exception 'Adjustment not found'; end if;
    if a.status not in ('draft', 'rejected') then raise exception 'Only draft or rejected adjustments can be edited'; end if;
    if not (public.has_permission(p_org, 'inventory', 'edit')
            or (a.created_by = v_uid and public.has_permission(p_org, 'inventory', 'create'))) then
      raise exception 'You do not have permission to edit this adjustment';
    end if;
    update stock_adjustments set adj_date = p_date, warehouse_id = p_warehouse, reason = p_reason,
      notes = nullif(btrim(coalesce(p_notes, '')), ''), status = 'draft', rejection_reason = null where id = p_id;
    delete from stock_adjustment_lines where adjustment_id = p_id;
  else
    if not public.has_permission(p_org, 'inventory', 'create') then
      raise exception 'You do not have permission to create stock adjustments';
    end if;
    insert into stock_adjustments (id, org_id, number, adj_date, warehouse_id, reason, status, notes, created_by)
    values (p_id, p_org, public.next_doc_number(p_org, 'stock_adjustment'), p_date, p_warehouse, p_reason, 'draft',
            nullif(btrim(coalesce(p_notes, '')), ''), v_uid);
  end if;

  for r in
    select * from jsonb_to_recordset(p_lines) as x(product_id uuid, quantity_change numeric, unit_cost numeric, note text)
  loop
    v_n := v_n + 1;
    v_qty := round(coalesce(r.quantity_change, 0), 3);
    if v_qty = 0 then raise exception 'Line %: enter a quantity', v_n; end if;
    select * into v_prod from products where id = r.product_id and org_id = p_org;
    if not found then raise exception 'Line %: choose an item', v_n; end if;
    if not v_prod.track_inventory or v_prod.item_type = 'service' then
      raise exception 'Line %: "%" does not track stock', v_n, v_prod.name;
    end if;
    if p_reason in ('damaged', 'expired', 'lost', 'issue') and v_qty > 0 then
      raise exception 'Line %: this reason can only reduce stock', v_n;
    end if;
    if p_reason = 'opening_stock' and v_qty < 0 then
      raise exception 'Line %: opening stock can only add stock', v_n;
    end if;
    if v_qty > 0 and (r.unit_cost is null or r.unit_cost < 0) then
      raise exception 'Line %: enter the unit cost of the stock being added', v_n;
    end if;
    insert into stock_adjustment_lines (org_id, adjustment_id, line_no, product_id, quantity_change, unit_cost, note)
    values (p_org, p_id, v_n, r.product_id, v_qty,
            case when v_qty > 0 then round(r.unit_cost, 4) else null end,
            nullif(btrim(coalesce(r.note, '')), ''));
  end loop;
  return p_id;
end $$;

create or replace function public.submit_stock_adjustment(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare a stock_adjustments%rowtype; v_uid uuid := auth.uid();
begin
  select * into a from stock_adjustments where id = p_id for update;
  if not found or not public.is_org_member(a.org_id) then raise exception 'Adjustment not found'; end if;
  if a.status not in ('draft', 'rejected') then raise exception 'Only draft or rejected adjustments can be submitted'; end if;
  if not (public.has_permission(a.org_id, 'inventory', 'edit')
          or (a.created_by = v_uid and public.has_permission(a.org_id, 'inventory', 'create'))) then
    raise exception 'You do not have permission to submit this adjustment';
  end if;
  update stock_adjustments set status = 'pending', submitted_at = now(), rejection_reason = null where id = p_id;
  perform public.notify_members_with_permission(a.org_id, 'inventory', 'approve',
    'Stock adjustment ' || a.number || ' needs approval', null, 'approval', 'stock_adjustment', a.id);
end $$;

create or replace function public.approve_stock_adjustment(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare a stock_adjustments%rowtype;
begin
  select * into a from stock_adjustments where id = p_id for update;
  if not found or not public.is_org_member(a.org_id) then raise exception 'Adjustment not found'; end if;
  if a.status <> 'pending' then raise exception 'Only pending adjustments can be approved'; end if;
  if not public.has_permission(a.org_id, 'inventory', 'approve') then raise exception 'You do not have permission to approve adjustments'; end if;
  update stock_adjustments set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_id;
  perform public._notify_user(a.org_id, a.created_by, 'Stock adjustment ' || a.number || ' approved', null, 'approval', 'stock_adjustment', a.id);
end $$;

create or replace function public.reject_stock_adjustment(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare a stock_adjustments%rowtype;
begin
  select * into a from stock_adjustments where id = p_id for update;
  if not found or not public.is_org_member(a.org_id) then raise exception 'Adjustment not found'; end if;
  if a.status <> 'pending' then raise exception 'Only pending adjustments can be rejected'; end if;
  if not public.has_permission(a.org_id, 'inventory', 'approve') then raise exception 'You do not have permission to reject adjustments'; end if;
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'Give a reason for the rejection'; end if;
  update stock_adjustments set status = 'rejected', rejection_reason = btrim(p_reason) where id = p_id;
  perform public._notify_user(a.org_id, a.created_by, 'Stock adjustment ' || a.number || ' was rejected', btrim(p_reason), 'approval', 'stock_adjustment', a.id);
end $$;

-- Applies the adjustment to stock and the books. Approves it first if needed.
create or replace function public.post_stock_adjustment(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  a stock_adjustments%rowtype; l record; v_val numeric; v_in numeric := 0; v_out numeric := 0;
  v_lines jsonb := '[]'::jsonb; v_voucher uuid; v_offset uuid; v_inventory uuid; v_expense uuid;
begin
  select * into a from stock_adjustments where id = p_id for update;
  if not found or not public.is_org_member(a.org_id) then raise exception 'Adjustment not found'; end if;
  if a.status not in ('draft', 'pending', 'approved') then raise exception 'This adjustment cannot be posted'; end if;
  if not public.has_permission(a.org_id, 'inventory', 'approve') then raise exception 'You do not have permission to post adjustments'; end if;
  if not exists (select 1 from stock_adjustment_lines where adjustment_id = p_id) then raise exception 'The adjustment has no lines'; end if;

  for l in select * from stock_adjustment_lines where adjustment_id = p_id order by line_no loop
    if l.quantity_change > 0 then
      v_val := public._stock_move(a.org_id, l.product_id, a.warehouse_id, a.adj_date, 'adjustment_in',
        l.quantity_change, l.unit_cost, 'stock_adjustment', a.id, l.id, a.number, a.reason);
      v_in := v_in + v_val;
    else
      v_val := public._stock_move(a.org_id, l.product_id, a.warehouse_id, a.adj_date, 'adjustment_out',
        l.quantity_change, null, 'stock_adjustment', a.id, l.id, a.number, a.reason);
      v_out := v_out - v_val;
    end if;
  end loop;

  v_inventory := public._sys_account(a.org_id, 'inventory');
  v_expense := public._sys_account(a.org_id, 'inventory_adjustment');
  v_offset := case when a.reason = 'opening_stock' then public._sys_account(a.org_id, 'opening_balance_equity') else v_expense end;
  if v_in > 0 then
    v_lines := v_lines || jsonb_build_object('account_id', v_inventory, 'debit', v_in, 'description', 'Stock added ' || a.number)
                       || jsonb_build_object('account_id', v_offset, 'credit', v_in, 'description', 'Stock added ' || a.number);
  end if;
  if v_out > 0 then
    v_lines := v_lines || jsonb_build_object('account_id', v_expense, 'debit', v_out, 'description', 'Stock written off ' || a.number)
                       || jsonb_build_object('account_id', v_inventory, 'credit', v_out, 'description', 'Stock written off ' || a.number);
  end if;
  if jsonb_array_length(v_lines) > 0 then
    v_voucher := public._post_new_voucher(a.org_id, 'journal', a.adj_date, 'Stock adjustment ' || a.number, null, null,
      v_lines, 'stock_adjustment', a.id);
  end if;

  update stock_adjustments set status = 'posted', posted_by = auth.uid(), posted_at = now(), voucher_id = v_voucher,
    approved_by = coalesce(approved_by, auth.uid()), approved_at = coalesce(approved_at, now())
  where id = p_id;
  perform public._notify_user(a.org_id, a.created_by, 'Stock adjustment ' || a.number || ' is posted', null, 'stock', 'stock_adjustment', a.id);
end $$;

create or replace function public.cancel_stock_adjustment(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare a stock_adjustments%rowtype; v_uid uuid := auth.uid(); v_reason text := btrim(coalesce(p_reason, '')); m stock_movements%rowtype;
begin
  select * into a from stock_adjustments where id = p_id for update;
  if not found or not public.is_org_member(a.org_id) then raise exception 'Adjustment not found'; end if;
  if v_reason = '' then raise exception 'Give a reason for cancelling'; end if;
  if a.status = 'cancelled' then raise exception 'This adjustment is already cancelled'; end if;
  if a.status = 'posted' then
    if not public.has_permission(a.org_id, 'inventory', 'approve') then raise exception 'You do not have permission to cancel a posted adjustment'; end if;
    for m in select * from stock_movements where source_type = 'stock_adjustment' and source_id = p_id and reversal_of is null loop
      perform public._stock_move(a.org_id, m.product_id, m.warehouse_id, current_date, 'reversal', -m.quantity,
        m.unit_cost, 'stock_adjustment', p_id, m.source_line_id, a.number, 'Reversal of ' || a.number, m.id);
    end loop;
    if a.voucher_id is not null then perform public._reverse_voucher(a.voucher_id, current_date, v_reason); end if;
  elsif not (public.has_permission(a.org_id, 'inventory', 'approve') or (a.created_by = v_uid and a.status in ('draft', 'rejected'))) then
    raise exception 'You do not have permission to cancel this adjustment';
  end if;
  update stock_adjustments set status = 'cancelled', cancel_reason = v_reason, cancelled_at = now() where id = p_id;
end $$;

create or replace function public.discard_stock_adjustment(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare a stock_adjustments%rowtype; v_uid uuid := auth.uid();
begin
  select * into a from stock_adjustments where id = p_id for update;
  if not found or not public.is_org_member(a.org_id) then raise exception 'Adjustment not found'; end if;
  if a.status not in ('draft', 'rejected') then raise exception 'Only draft or rejected adjustments can be deleted'; end if;
  if not (public.has_permission(a.org_id, 'inventory', 'delete') or (a.created_by = v_uid and public.has_permission(a.org_id, 'inventory', 'create'))) then
    raise exception 'You do not have permission to delete this adjustment';
  end if;
  delete from attachments where org_id = a.org_id and entity_type = 'stock_adjustment' and entity_id = p_id;
  delete from stock_adjustments where id = p_id;
end $$;

-- ---------------------------------------------------------------------
-- Read functions for stock and purchasing screens
-- ---------------------------------------------------------------------

-- Stock by item. Cost and value are hidden from roles without financial data.
create or replace function public.stock_summary(p_org uuid, p_warehouse uuid default null)
returns table (
  product_id uuid, sku text, name text, unit text, category text, quantity numeric,
  avg_cost numeric, value numeric, min_stock numeric, reorder_level numeric, is_active boolean
) language plpgsql stable security definer set search_path = public as $$
declare v_fin boolean;
begin
  if not public.has_permission(p_org, 'inventory', 'view') then raise exception 'Access denied'; end if;
  v_fin := public.has_permission(p_org, 'financial_data', 'view');
  return query
  select p.id, p.sku, p.name, u.name, c.name,
         coalesce(sum(b.quantity), 0)::numeric,
         case when not v_fin then null
              when coalesce(sum(b.quantity), 0) > 0 then round(sum(b.value) / sum(b.quantity), 4)
              else 0::numeric end,
         case when v_fin then coalesce(sum(b.value), 0)::numeric else null end,
         p.min_stock, p.reorder_level, p.is_active
  from products p
  left join lookups u on u.id = p.unit_id
  left join lookups c on c.id = p.category_id
  left join stock_balances b on b.product_id = p.id and (p_warehouse is null or b.warehouse_id = p_warehouse)
  where p.org_id = p_org and p.track_inventory and p.item_type <> 'service'
  group by p.id, u.name, c.name
  having p.is_active or coalesce(sum(b.quantity), 0) <> 0
  order by p.name;
end $$;

-- Quantities only, for anyone who buys, sells or stocks items.
create or replace function public.stock_on_hand(p_org uuid, p_warehouse uuid default null)
returns table (product_id uuid, warehouse_id uuid, quantity numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.has_permission(p_org, 'inventory', 'view') or public.has_permission(p_org, 'purchase', 'view')
          or public.has_permission(p_org, 'sales', 'view')) then
    raise exception 'Access denied';
  end if;
  return query
  select b.product_id, b.warehouse_id, b.quantity
  from stock_balances b
  where b.org_id = p_org and b.quantity <> 0 and (p_warehouse is null or b.warehouse_id = p_warehouse);
end $$;

-- Movement history of one item with a running quantity (newest first).
create or replace function public.stock_ledger(
  p_org uuid, p_product uuid, p_warehouse uuid default null, p_from date default null, p_to date default null
) returns table (
  movement_id uuid, movement_date date, movement_type text, warehouse_id uuid, warehouse text,
  quantity numeric, unit_cost numeric, value numeric, running_qty numeric, reference text,
  narration text, source_type text, source_id uuid, created_at timestamptz
) language plpgsql stable security definer set search_path = public as $$
declare v_fin boolean;
begin
  if not public.has_permission(p_org, 'inventory', 'view') then raise exception 'Access denied'; end if;
  v_fin := public.has_permission(p_org, 'financial_data', 'view');
  return query
  with m as (
    select sm.*, sum(sm.quantity) over (order by sm.movement_date, sm.created_at, sm.id) as run
    from stock_movements sm
    where sm.org_id = p_org and sm.product_id = p_product and (p_warehouse is null or sm.warehouse_id = p_warehouse)
  )
  select m.id, m.movement_date, m.movement_type, m.warehouse_id, w.name, m.quantity,
         case when v_fin then m.unit_cost else null end,
         case when v_fin then m.value else null end,
         m.run, m.reference, m.narration, m.source_type, m.source_id, m.created_at
  from m join warehouses w on w.id = m.warehouse_id
  where (p_from is null or m.movement_date >= p_from) and (p_to is null or m.movement_date <= p_to)
  order by m.movement_date desc, m.created_at desc, m.id desc;
end $$;

-- Most recent receipt cost of each item, with the supplier it came from.
create or replace function public.last_purchase_prices(p_org uuid)
returns table (product_id uuid, unit_cost numeric, purchase_date date, supplier_id uuid, supplier_name text, reference text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.has_permission(p_org, 'purchase', 'view') or public.has_permission(p_org, 'inventory', 'view')) then
    raise exception 'Access denied';
  end if;
  return query
  select distinct on (m.product_id) m.product_id, m.unit_cost, m.movement_date, d.party_id, pa.name, m.reference
  from stock_movements m
  left join trade_documents d on d.id = m.source_id
  left join parties pa on pa.id = d.party_id
  where m.org_id = p_org and m.movement_type = 'purchase_receipt'
    and not exists (select 1 from stock_movements r where r.reversal_of = m.id)
  order by m.product_id, m.movement_date desc, m.created_at desc;
end $$;

-- Receipt lines that have not been fully billed yet, for one supplier.
create or replace function public.unbilled_receipt_lines(p_org uuid, p_party uuid, p_exclude_bill uuid default null)
returns table (
  receipt_line_id uuid, receipt_id uuid, receipt_number text, receipt_date date, product_id uuid,
  product_name text, received_qty numeric, billed_qty numeric, remaining_qty numeric,
  receipt_unit_cost numeric, order_unit_price numeric, order_discount_per_unit numeric, tax_rate_id uuid
) language sql stable as $$
  select gl.id, gd.id, gd.number, gd.doc_date, gl.product_id, pr.name, gl.quantity, billed.qty,
         gl.quantity - billed.qty, gl.unit_price, pol.unit_price,
         case when pol.id is not null and pol.quantity > 0 then round(pol.discount_amount / pol.quantity, 4) else 0 end,
         coalesce(pol.tax_rate_id, pr.tax_rate_id)
  from trade_document_lines gl
  join trade_documents gd on gd.id = gl.document_id and gd.doc_type = 'goods_receipt' and gd.status = 'posted'
                         and gd.org_id = p_org and gd.party_id = p_party
  join products pr on pr.id = gl.product_id
  left join trade_document_lines pol on pol.id = gl.source_line_id
  cross join lateral (
    select coalesce(sum(b.quantity), 0) as qty
    from trade_document_lines b join trade_documents bd on bd.id = b.document_id
    where b.source_line_id = gl.id and bd.doc_type = 'supplier_bill' and bd.status <> 'cancelled'
      and (p_exclude_bill is null or bd.id <> p_exclude_bill)
  ) billed
  where gl.quantity - billed.qty > 0
  order by gd.doc_date, gd.number, gl.line_no;
$$;

-- Order lines for services and non-stock items that have not been fully billed yet.
create or replace function public.unbilled_order_lines(p_org uuid, p_party uuid, p_exclude_bill uuid default null)
returns table (
  order_line_id uuid, order_id uuid, order_number text, order_date date, product_id uuid, description text,
  ordered_qty numeric, billed_qty numeric, remaining_qty numeric, unit_price numeric,
  discount_per_unit numeric, tax_rate_id uuid
) language sql stable as $$
  select l.id, d.id, d.number, d.doc_date, l.product_id, coalesce(l.description, pr.name), l.quantity, billed.qty,
         l.quantity - billed.qty, l.unit_price, round(l.discount_amount / l.quantity, 4), l.tax_rate_id
  from trade_document_lines l
  join trade_documents d on d.id = l.document_id and d.doc_type = 'purchase_order'
                        and d.status in ('approved', 'partial', 'received', 'closed')
                        and d.org_id = p_org and d.party_id = p_party
  left join products pr on pr.id = l.product_id
  cross join lateral (
    select coalesce(sum(b.quantity), 0) as qty
    from trade_document_lines b join trade_documents bd on bd.id = b.document_id
    where b.source_line_id = l.id and bd.doc_type = 'supplier_bill' and bd.status <> 'cancelled'
      and (p_exclude_bill is null or bd.id <> p_exclude_bill)
  ) billed
  where (l.product_id is null or not (pr.track_inventory and pr.item_type <> 'service'))
    and l.quantity - billed.qty > 0
  order by d.doc_date, d.number, l.line_no;
$$;

-- Ordered, received and billed quantities for each line of a purchase order.
create or replace function public.purchase_order_progress(p_doc uuid)
returns table (line_id uuid, ordered_qty numeric, received_qty numeric, billed_qty numeric)
language sql stable as $$
  select l.id, l.quantity,
    coalesce((select sum(g.quantity) from trade_document_lines g join trade_documents gd on gd.id = g.document_id
              where g.source_line_id = l.id and gd.doc_type = 'goods_receipt' and gd.status = 'posted'), 0),
    coalesce((select sum(b.quantity) from trade_document_lines b join trade_documents bd on bd.id = b.document_id
              where bd.doc_type = 'supplier_bill' and bd.status <> 'cancelled'
                and (b.source_line_id = l.id
                     or b.source_line_id in (
                       select g2.id from trade_document_lines g2 join trade_documents gd2 on gd2.id = g2.document_id
                       where g2.source_line_id = l.id and gd2.doc_type = 'goods_receipt' and gd2.status = 'posted'))), 0)
  from trade_document_lines l
  where l.document_id = p_doc
  order by l.line_no;
$$;

-- Documents linked to this one: where it came from and what was created from it.
create or replace function public.related_documents(p_doc uuid)
returns table (id uuid, doc_type text, number text, status text, doc_date date, total numeric, relation text)
language sql stable as $$
  with mine as (select l.id from trade_document_lines l where l.document_id = p_doc),
  links as (
    select d.id as doc_id, 'source' as relation from trade_documents d
      where d.id = (select x.source_id from trade_documents x where x.id = p_doc)
    union
    select d.id, 'created' from trade_documents d where d.source_id = p_doc
    union
    select l.document_id, 'source' from trade_document_lines l
      where l.id in (select m.source_line_id from trade_document_lines m where m.document_id = p_doc)
    union
    select c.document_id, 'created' from trade_document_lines c where c.source_line_id in (select id from mine)
  )
  select d.id, d.doc_type, d.number, d.status, d.doc_date, d.total, min(k.relation)
  from links k join trade_documents d on d.id = k.doc_id
  where d.id <> p_doc
  group by d.id, d.doc_type, d.number, d.status, d.doc_date, d.total
  order by d.doc_date, d.number;
$$;

-- ---------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
           where p.pronamespace = 'public'::regnamespace
             and p.proname in ('save_purchase_document', 'submit_document', 'approve_document', 'reject_document',
                               'discard_document', 'cancel_document', 'close_purchase_order', 'post_goods_receipt',
                               'post_supplier_bill', 'save_stock_adjustment', 'submit_stock_adjustment',
                               'approve_stock_adjustment', 'reject_stock_adjustment', 'post_stock_adjustment',
                               'cancel_stock_adjustment', 'discard_stock_adjustment', 'stock_summary',
                               'stock_on_hand', 'stock_ledger', 'last_purchase_prices', 'unbilled_receipt_lines', 'unbilled_order_lines',
                               'purchase_order_progress', 'related_documents')
  loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;

  for f in select p.oid::regprocedure from pg_proc p
           where p.pronamespace = 'public'::regnamespace
             and p.proname in ('_sys_account', '_doc_can', '_doc_label', '_stock_move', '_sync_requisition',
                               '_sync_po_status', 'seed_trade_defaults')
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Backfill organizations created before this migration
-- ---------------------------------------------------------------------
do $$
declare o record;
begin
  for o in select id from organizations loop
    perform public.seed_trade_defaults(o.id);
  end loop;
end $$;
