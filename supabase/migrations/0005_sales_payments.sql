-- =====================================================================
-- EZ ERP  |  0005  Sales and payments (Phase 1, step 1D, part 2)
--
--   * Sales quotations, sales orders and sales invoices on the shared
--     trade_documents / trade_document_lines tables from 0004.
--   * Posting an invoice: Dr Accounts receivable, Cr Sales revenue and
--     Output tax payable, stock issued at weighted average cost with
--     Dr Cost of goods sold / Cr Inventory. Customer credit limit check.
--   * Opening balances entered as posted opening invoices and bills, so
--     they age and are paid like any other document.
--   * Customer receipts and supplier payments with allocation to invoices
--     and bills, partial payments, advances (customer credit balance and
--     advance to supplier) and controlled reversal.
--   * Receivable and payable aging, party statements and dues.
--
-- Requires 0001 to 0004. Receivables and payables are derived from
-- documents and allocations; nothing is stored twice.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Columns added to the shared document table
-- ---------------------------------------------------------------------
alter table public.trade_documents add column is_opening boolean not null default false;
alter table public.trade_documents add column credit_overridden boolean not null default false;
create index trade_documents_opening_idx on public.trade_documents(org_id, doc_type) where is_opening;

-- ---------------------------------------------------------------------
-- Document numbering for the new records
-- ---------------------------------------------------------------------
create or replace function public.seed_sales_defaults(p_org uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform set_config('app.skip_audit', 'on', true);
  insert into doc_sequences (org_id, doc_type, prefix) values
    (p_org, 'opening_invoice', 'OINV'),
    (p_org, 'opening_bill', 'OBILL'),
    (p_org, 'customer_receipt', 'RCT'),
    (p_org, 'supplier_payment', 'SPY')
  on conflict (org_id, doc_type) do nothing;
  perform set_config('app.skip_audit', 'off', true);
end $$;

create or replace function public.trg_seed_org_sales()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.seed_sales_defaults(new.id);
  return new;
end $$;
create trigger trg_seed_org_sales after insert on public.organizations
  for each row execute function public.trg_seed_org_sales();

-- ---------------------------------------------------------------------
-- Payments and allocations
-- A payment is money received from a customer (receipt) or paid to a
-- supplier (payment). It is posted the moment it is recorded. The part
-- that is not allocated to a document stays as an advance.
-- ---------------------------------------------------------------------
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  kind text not null check (kind in ('receipt', 'payment')),
  number text not null,
  pay_date date not null default current_date,
  party_id uuid not null references public.parties(id) on delete restrict,
  financial_account_id uuid not null references public.financial_accounts(id) on delete restrict,
  method_id uuid references public.lookups(id) on delete set null,
  amount numeric(18,2) not null check (amount > 0),
  reference text,
  notes text,
  status text not null default 'posted' check (status in ('posted', 'cancelled')),
  voucher_id uuid references public.vouchers(id) on delete set null,
  cancel_reason text,
  cancelled_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, number)
);
create index payments_list_idx on public.payments(org_id, kind, pay_date desc);
create index payments_party_idx on public.payments(party_id);
create trigger payments_updated before update on public.payments
  for each row execute function public.set_updated_at();

create table public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  payment_id uuid not null references public.payments(id) on delete restrict,
  document_id uuid not null references public.trade_documents(id) on delete restrict,
  amount numeric(18,2) not null check (amount > 0),
  alloc_date date not null,
  -- Set when an advance was applied after the payment was recorded.
  voucher_id uuid references public.vouchers(id) on delete set null,
  reversed_at timestamptz,
  created_at timestamptz not null default now()
);
create index payment_allocations_payment_idx on public.payment_allocations(payment_id);
create index payment_allocations_document_idx on public.payment_allocations(document_id) where reversed_at is null;

-- A posted payment can only be cancelled. Cancelled payments are history.
create or replace function public.payments_guard()
returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Payments cannot be deleted. Cancel the payment to reverse it.';
  end if;
  if old.status = 'cancelled' then
    raise exception 'A cancelled payment cannot be changed';
  end if;
  if new.status <> 'cancelled'
     or (to_jsonb(new) - 'status' - 'cancelled_at' - 'cancel_reason' - 'updated_at')
        is distinct from (to_jsonb(old) - 'status' - 'cancelled_at' - 'cancel_reason' - 'updated_at') then
    raise exception 'A posted payment cannot be changed. Cancel it to reverse its effect.';
  end if;
  return new;
end $$;
create trigger payments_guard before update or delete on public.payments
  for each row execute function public.payments_guard();

-- An allocation is never edited or deleted; it can only be marked reversed.
create or replace function public.payment_allocations_guard()
returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Allocations cannot be deleted. Unapply the payment instead.';
  end if;
  if old.reversed_at is not null
     or (to_jsonb(new) - 'reversed_at') is distinct from (to_jsonb(old) - 'reversed_at') then
    raise exception 'An allocation cannot be changed. Unapply it instead.';
  end if;
  return new;
end $$;
create trigger payment_allocations_guard before update or delete on public.payment_allocations
  for each row execute function public.payment_allocations_guard();

-- An invoice or bill with payments applied cannot be cancelled until they are unapplied.
create or replace function public.trade_documents_payment_guard()
returns trigger language plpgsql as $$
begin
  if old.status = 'posted' and new.status = 'cancelled' and old.doc_type in ('sales_invoice', 'supplier_bill')
     and exists (select 1 from payment_allocations a where a.document_id = old.id and a.reversed_at is null) then
    raise exception 'This % has payments applied to it. Cancel the payments or unapply them first.',
      case old.doc_type when 'sales_invoice' then 'invoice' else 'bill' end;
  end if;
  return new;
end $$;
create trigger trade_documents_payment_guard before update on public.trade_documents
  for each row execute function public.trade_documents_payment_guard();

-- ---------------------------------------------------------------------
-- Row level security: reads only. Writes go through the functions below.
-- ---------------------------------------------------------------------
alter table public.payments enable row level security;
alter table public.payment_allocations enable row level security;

create policy payments_select on public.payments for select to authenticated using (
  public.has_permission(org_id, 'finance', 'view')
  or case kind when 'receipt' then public.has_permission(org_id, 'sales', 'view')
       else public.has_permission(org_id, 'purchase', 'view') end);

create policy payment_allocations_select on public.payment_allocations for select to authenticated using (
  exists (select 1 from public.payments p where p.id = payment_id));

select public.enable_audit('public.payments');

-- ---------------------------------------------------------------------
-- Balances. Open amounts are always computed from documents and active
-- allocations.
-- ---------------------------------------------------------------------
create view public.document_balances with (security_invoker = true) as
select d.id as document_id, d.org_id, d.doc_type, d.party_id, d.number, d.reference, d.doc_date, d.due_date,
       d.is_opening, d.total,
       coalesce(a.paid, 0)::numeric(18,2) as paid,
       (d.total - coalesce(a.paid, 0))::numeric(18,2) as balance,
       case when d.total - coalesce(a.paid, 0) <= 0 then 'paid'
            when coalesce(a.paid, 0) > 0 then 'partial'
            else 'unpaid' end as payment_status,
       case when d.total - coalesce(a.paid, 0) > 0 and coalesce(d.due_date, d.doc_date) < current_date
            then current_date - coalesce(d.due_date, d.doc_date) else 0 end as days_overdue
from public.trade_documents d
left join lateral (
  select sum(x.amount) as paid from public.payment_allocations x
  where x.document_id = d.id and x.reversed_at is null
) a on true
where d.doc_type in ('sales_invoice', 'supplier_bill') and d.status = 'posted';

create view public.payment_balances with (security_invoker = true) as
select p.id as payment_id, p.org_id, p.kind, p.number, p.pay_date, p.party_id, p.amount, p.status,
       coalesce(a.allocated, 0)::numeric(18,2) as allocated,
       (case when p.status = 'posted' then p.amount - coalesce(a.allocated, 0) else 0 end)::numeric(18,2) as unallocated
from public.payments p
left join lateral (
  select sum(x.amount) as allocated from public.payment_allocations x
  where x.payment_id = p.id and x.reversed_at is null
) a on true;

grant select on public.document_balances, public.payment_balances to authenticated;

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------
-- Who may record, apply or reverse payments.
create or replace function public._pay_can(p_org uuid, p_kind text, p_action text)
returns boolean language sql stable security definer set search_path = public as $$
  select case p_action
    when 'create' then public.has_permission(p_org, 'finance', 'create')
                       or (p_kind = 'receipt' and public.has_permission(p_org, 'sales', 'approve'))
    when 'approve' then public.has_permission(p_org, 'finance', 'approve')
    else false end;
$$;

-- What a customer owes right now: open invoices less unapplied receipts.
create or replace function public._party_exposure(p_org uuid, p_party uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select sum(b.balance) from document_balances b
                   where b.org_id = p_org and b.party_id = p_party and b.doc_type = 'sales_invoice'), 0)
       - coalesce((select sum(x.unallocated) from payment_balances x
                   where x.org_id = p_org and x.party_id = p_party and x.kind = 'receipt' and x.status = 'posted'), 0);
$$;

-- Returns stock that an invoice issued, at exactly the value it left at.
create or replace function public._stock_reverse(p_movement uuid, p_date date, p_ref text, p_narration text)
returns numeric language plpgsql security definer set search_path = public as $$
declare m stock_movements%rowtype; b stock_balances%rowtype; v_qty numeric; v_new numeric; v_avg numeric; v_val numeric;
begin
  select * into m from stock_movements where id = p_movement;
  if not found then raise exception 'Stock movement not found'; end if;
  if m.quantity >= 0 then raise exception 'Only outgoing stock movements are returned here'; end if;
  select * into b from stock_balances where product_id = m.product_id and warehouse_id = m.warehouse_id for update;
  v_val := abs(m.value);
  v_qty := b.quantity + abs(m.quantity);
  v_new := b.value + v_val;
  v_avg := case when v_qty > 0 then round(v_new / v_qty, 4) else b.avg_cost end;
  update stock_balances set quantity = v_qty, value = v_new, avg_cost = v_avg, updated_at = now()
  where product_id = m.product_id and warehouse_id = m.warehouse_id;
  insert into stock_movements (org_id, product_id, warehouse_id, movement_date, movement_type, quantity, unit_cost,
                               value, source_type, source_id, source_line_id, reference, narration, reversal_of, created_by)
  values (m.org_id, m.product_id, m.warehouse_id, p_date, 'reversal', abs(m.quantity), m.unit_cost, v_val,
          m.source_type, m.source_id, m.source_line_id, p_ref, p_narration, m.id, auth.uid());
  return v_val;
end $$;

-- A quotation is Converted while a live order exists, otherwise Accepted.
create or replace function public._sync_quotation(p_q uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_q is null then return; end if;
  update trade_documents set status = case when exists (
      select 1 from trade_documents so where so.source_id = p_q and so.doc_type = 'sales_order' and so.status <> 'cancelled'
    ) then 'converted' else 'accepted' end
  where id = p_q and doc_type = 'sales_quotation' and status in ('sent', 'accepted', 'converted');
end $$;

-- An order is Partial or Invoiced according to its posted invoices.
create or replace function public._sync_so_status(p_so uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_status text; v_all boolean; v_inv numeric; v_lines int;
begin
  if p_so is null then return; end if;
  select status into v_status from trade_documents where id = p_so and doc_type = 'sales_order';
  if v_status is null or v_status not in ('approved', 'partial', 'invoiced') then return; end if;
  select coalesce(bool_and(inv.qty >= l.quantity), true), coalesce(sum(inv.qty), 0), count(*)
    into v_all, v_inv, v_lines
  from trade_document_lines l
  cross join lateral (
    select coalesce(sum(g.quantity), 0) as qty
    from trade_document_lines g join trade_documents gd on gd.id = g.document_id
    where g.source_line_id = l.id and gd.doc_type = 'sales_invoice' and gd.status = 'posted'
  ) inv
  where l.document_id = p_so;
  update trade_documents set status = case
      when v_lines = 0 then 'approved'
      when v_all then 'invoiced'
      when v_inv > 0 then 'partial'
      else 'approved' end
  where id = p_so;
end $$;

-- ---------------------------------------------------------------------
-- Save a sales document (quotation, order or invoice).
-- Prices come from the app; amounts, taxes and links are checked and
-- calculated here.
-- ---------------------------------------------------------------------
create or replace function public.save_sales_document(
  p_id uuid, p_org uuid, p_type text, p_party uuid, p_date date, p_due date, p_expected date,
  p_branch uuid, p_warehouse uuid, p_reference text, p_notes text, p_source uuid, p_lines jsonb
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
  v_any_stock boolean := false;
  v_qty numeric; v_price numeric; v_gross numeric; v_disc numeric; v_net numeric;
  v_tax numeric; v_trate numeric; v_tax_id uuid; v_account uuid; v_srcline uuid;
  v_remaining numeric;
  v_sub numeric := 0; v_dsum numeric := 0; v_tsum numeric := 0;
  v_due date; v_ref text := nullif(btrim(coalesce(p_reference, '')), '');
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  if not public.is_org_member(p_org) then raise exception 'Access denied'; end if;
  if p_type not in ('sales_quotation', 'sales_order', 'sales_invoice') then raise exception 'Unsupported document type'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Add at least one line';
  end if;
  if p_date is null then raise exception 'Choose a date'; end if;

  select * into d from trade_documents where id = p_id;
  if found then
    v_exists := true;
    if d.org_id <> p_org or d.doc_type <> p_type then raise exception 'Document not found'; end if;
    if d.is_opening then raise exception 'Opening balances cannot be edited. Cancel it and enter it again.'; end if;
    if d.status not in ('draft', 'rejected') then raise exception 'Only draft or rejected documents can be edited'; end if;
    if not (public._doc_can(p_org, p_type, 'edit') or (d.created_by = v_uid and public._doc_can(p_org, p_type, 'create'))) then
      raise exception 'You do not have permission to edit this document';
    end if;
  elsif not public._doc_can(p_org, p_type, 'create') then
    raise exception 'You do not have permission to create this document';
  end if;

  -- Header checks
  if p_party is null then raise exception 'Choose a customer'; end if;
  select * into v_party from parties where id = p_party and org_id = p_org;
  if not found or not v_party.is_customer then raise exception 'Choose a valid customer'; end if;
  if not v_party.is_active then raise exception 'This customer is archived'; end if;
  if p_warehouse is not null and not exists (
    select 1 from warehouses where id = p_warehouse and org_id = p_org and is_active) then
    raise exception 'Choose a valid warehouse';
  end if;
  if p_branch is not null and not exists (select 1 from branches where id = p_branch and org_id = p_org) then
    raise exception 'Choose a valid branch';
  end if;

  if p_source is not null then
    select * into v_srcdoc from trade_documents where id = p_source and org_id = p_org;
    if not found then raise exception 'The source document was not found'; end if;
    if v_srcdoc.party_id is distinct from p_party then raise exception 'The customer must match the source document'; end if;
    if p_type = 'sales_order' then
      if v_srcdoc.doc_type <> 'sales_quotation' or v_srcdoc.status not in ('sent', 'accepted') then
        raise exception 'Only a sent or accepted quotation can be converted to a sales order';
      end if;
    elsif p_type = 'sales_invoice' then
      if v_srcdoc.doc_type <> 'sales_order' or v_srcdoc.status not in ('approved', 'partial') then
        raise exception 'An invoice can only be created from an approved sales order that is still open';
      end if;
    else
      raise exception 'A quotation cannot be created from another document';
    end if;
  end if;

  v_due := case when p_type = 'sales_invoice' then coalesce(p_due, p_date + coalesce(v_party.payment_terms_days, 0)) else null end;
  if v_due is not null and v_due < p_date then raise exception 'The due date cannot be before the invoice date'; end if;

  -- Header
  if not v_exists then
    insert into trade_documents (id, org_id, doc_type, number, doc_date, due_date, expected_date, status,
                                 party_id, branch_id, warehouse_id, source_id, reference, notes, created_by)
    values (p_id, p_org, p_type, public.next_doc_number(p_org, p_type), p_date, v_due, p_expected, 'draft',
            p_party, p_branch, p_warehouse, p_source, v_ref, nullif(btrim(coalesce(p_notes, '')), ''), v_uid);
  else
    update trade_documents set
      doc_date = p_date, due_date = v_due, expected_date = p_expected, status = 'draft',
      party_id = p_party, branch_id = p_branch, warehouse_id = p_warehouse,
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
    if v_stock then v_any_stock := true; end if;

    v_price := round(coalesce(r.unit_price, 0), 4);
    if v_price < 0 then raise exception 'Line %: the price cannot be negative', v_n; end if;
    v_gross := round(v_qty * v_price, 2);
    v_disc := round(coalesce(r.discount_amount, 0), 2);
    if v_disc < 0 or v_disc > v_gross then raise exception 'Line %: the discount cannot exceed the line amount', v_n; end if;
    v_net := v_gross - v_disc;

    v_tax := 0; v_trate := 0; v_tax_id := null;
    if r.tax_rate_id is not null then
      select * into v_rate from tax_rates
      where id = r.tax_rate_id and org_id = p_org and is_active and applies_to in ('sales', 'both');
      if not found then raise exception 'Line %: choose a valid tax rate', v_n; end if;
      v_tax_id := v_rate.id; v_trate := v_rate.rate; v_tax := round(v_net * v_trate / 100, 2);
    end if;

    v_account := null; v_srcline := null;
    if p_type = 'sales_invoice' and r.account_id is not null then
      select * into v_acct from accounts where id = r.account_id and org_id = p_org;
      if not found or v_acct.is_group or not v_acct.is_active or v_acct.account_type <> 'income' then
        raise exception 'Line %: choose an active income account', v_n;
      end if;
      v_account := v_acct.id;
    end if;

    if r.source_line_id is not null and p_type <> 'sales_quotation' then
      if p_source is null then raise exception 'Line %: this line is linked to a document that was not selected', v_n; end if;
      select * into v_src from trade_document_lines where id = r.source_line_id;
      if not found or v_src.document_id is distinct from p_source then
        raise exception 'Line %: this line does not belong to the source document', v_n;
      end if;
      if v_src.product_id is distinct from r.product_id then
        raise exception 'Line %: the item differs from the source line', v_n;
      end if;
      if p_type = 'sales_invoice' then
        select v_src.quantity - coalesce(sum(g.quantity), 0) into v_remaining
        from trade_document_lines g join trade_documents gd on gd.id = g.document_id
        where g.source_line_id = v_src.id and gd.doc_type = 'sales_invoice' and gd.status <> 'cancelled' and gd.id <> p_id;
        if v_qty > v_remaining then
          raise exception 'Line %: only % remain to be invoiced on this order', v_n, trim_scale(v_remaining);
        end if;
      end if;
      v_srcline := v_src.id;
    end if;

    insert into trade_document_lines (org_id, document_id, line_no, product_id, description, quantity,
                                      unit_price, discount_amount, tax_rate_id, tax_rate, tax_amount,
                                      net_amount, line_total, account_id, source_line_id)
    values (p_org, p_id, v_n, r.product_id, nullif(btrim(coalesce(r.description, '')), ''), v_qty,
            v_price, v_disc, v_tax_id, v_trate, v_tax, v_net, v_net + v_tax, v_account, v_srcline);

    v_sub := v_sub + v_gross; v_dsum := v_dsum + v_disc; v_tsum := v_tsum + v_tax;
  end loop;

  if p_type = 'sales_invoice' and v_any_stock and p_warehouse is null then
    raise exception 'Choose the warehouse the goods are issued from';
  end if;

  update trade_documents
  set subtotal = v_sub, discount_total = v_dsum, tax_total = v_tsum, total = v_sub - v_dsum + v_tsum
  where id = p_id;

  if p_type = 'sales_order' then perform public._sync_quotation(p_source); end if;
  return p_id;
end $$;

-- ---------------------------------------------------------------------
-- Quotation: send, record the customer's answer, reopen
-- ---------------------------------------------------------------------
create or replace function public.mark_quotation_sent(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d trade_documents%rowtype; v_uid uuid := auth.uid();
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) or d.doc_type <> 'sales_quotation' then raise exception 'Quotation not found'; end if;
  if d.status <> 'draft' then raise exception 'Only a draft quotation can be sent'; end if;
  if not (public._doc_can(d.org_id, d.doc_type, 'edit') or (d.created_by = v_uid and public._doc_can(d.org_id, d.doc_type, 'create'))) then
    raise exception 'You do not have permission to send this quotation';
  end if;
  if not exists (select 1 from trade_document_lines where document_id = p_id) then raise exception 'Add at least one line before sending'; end if;
  update trade_documents set status = 'sent', submitted_at = now(), rejection_reason = null where id = p_id;
end $$;

create or replace function public.set_quotation_outcome(p_id uuid, p_outcome text, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare d trade_documents%rowtype; v_uid uuid := auth.uid();
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) or d.doc_type <> 'sales_quotation' then raise exception 'Quotation not found'; end if;
  if p_outcome not in ('accepted', 'rejected') then raise exception 'Choose accepted or declined'; end if;
  if d.status <> 'sent' then raise exception 'Only a sent quotation can be marked as accepted or declined'; end if;
  if not (public._doc_can(d.org_id, d.doc_type, 'edit') or d.created_by = v_uid) then
    raise exception 'You do not have permission to update this quotation';
  end if;
  if p_outcome = 'rejected' and btrim(coalesce(p_reason, '')) = '' then raise exception 'Note why the customer declined'; end if;
  update trade_documents set status = p_outcome,
    rejection_reason = case when p_outcome = 'rejected' then btrim(p_reason) else null end
  where id = p_id;
end $$;

-- Brings a sent or accepted quotation back to draft so it can be changed and sent again.
create or replace function public.reopen_quotation(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d trade_documents%rowtype; v_uid uuid := auth.uid();
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) or d.doc_type <> 'sales_quotation' then raise exception 'Quotation not found'; end if;
  if d.status not in ('sent', 'accepted') then raise exception 'Only a sent or accepted quotation can be reopened'; end if;
  if not (public._doc_can(d.org_id, d.doc_type, 'edit') or d.created_by = v_uid) then
    raise exception 'You do not have permission to reopen this quotation';
  end if;
  update trade_documents set status = 'draft', rejection_reason = null where id = p_id;
end $$;

-- ---------------------------------------------------------------------
-- Approval workflow for sales orders and invoices
-- ---------------------------------------------------------------------
create or replace function public.submit_sales_document(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d trade_documents%rowtype; v_uid uuid := auth.uid();
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) then raise exception 'Document not found'; end if;
  if d.doc_type not in ('sales_order', 'sales_invoice') then raise exception 'This document is not submitted for approval'; end if;
  if d.status not in ('draft', 'rejected') then raise exception 'Only draft or rejected documents can be submitted'; end if;
  if not (public._doc_can(d.org_id, d.doc_type, 'edit') or (d.created_by = v_uid and public._doc_can(d.org_id, d.doc_type, 'create'))) then
    raise exception 'You do not have permission to submit this document';
  end if;
  if not exists (select 1 from trade_document_lines where document_id = p_id) then raise exception 'Add at least one line before submitting'; end if;
  update trade_documents set status = 'pending', submitted_at = now(), rejection_reason = null where id = p_id;
  perform public.notify_members_with_permission(
    d.org_id, 'sales', 'approve', public._doc_label(d.doc_type) || ' ' || d.number || ' needs approval',
    'Total ' || to_char(d.total, 'FM999,999,999,990.00'), 'approval', d.doc_type, d.id);
end $$;

create or replace function public.approve_sales_document(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d trade_documents%rowtype;
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) then raise exception 'Document not found'; end if;
  if d.doc_type not in ('sales_order', 'sales_invoice') then raise exception 'This document is not approved here'; end if;
  if d.status <> 'pending' then raise exception 'Only pending documents can be approved'; end if;
  if not public._doc_can(d.org_id, d.doc_type, 'approve') then raise exception 'You do not have permission to approve this document'; end if;
  update trade_documents set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_id;
  perform public._notify_user(d.org_id, d.created_by, public._doc_label(d.doc_type) || ' ' || d.number || ' approved', null, 'approval', d.doc_type, d.id);
end $$;

create or replace function public.reject_sales_document(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare d trade_documents%rowtype;
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) then raise exception 'Document not found'; end if;
  if d.doc_type not in ('sales_order', 'sales_invoice') then raise exception 'This document is not approved here'; end if;
  if d.status <> 'pending' then raise exception 'Only pending documents can be rejected'; end if;
  if not public._doc_can(d.org_id, d.doc_type, 'approve') then raise exception 'You do not have permission to reject this document'; end if;
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'Give a reason for the rejection'; end if;
  update trade_documents set status = 'rejected', rejection_reason = btrim(p_reason) where id = p_id;
  perform public._notify_user(d.org_id, d.created_by, public._doc_label(d.doc_type) || ' ' || d.number || ' was rejected', btrim(p_reason), 'approval', d.doc_type, d.id);
end $$;

create or replace function public.discard_sales_document(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d trade_documents%rowtype; v_uid uuid := auth.uid();
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) or d.doc_type not in ('sales_quotation', 'sales_order', 'sales_invoice') then
    raise exception 'Document not found';
  end if;
  if d.status not in ('draft', 'rejected') then raise exception 'Only draft or rejected documents can be deleted'; end if;
  if not (public._doc_can(d.org_id, d.doc_type, 'delete') or (d.created_by = v_uid and public._doc_can(d.org_id, d.doc_type, 'create'))) then
    raise exception 'You do not have permission to delete this document';
  end if;
  delete from attachments where org_id = d.org_id and entity_type = d.doc_type and entity_id = p_id;
  delete from trade_documents where id = p_id;
  if d.doc_type = 'sales_order' then perform public._sync_quotation(d.source_id); end if;
end $$;

-- Stops further invoicing on an order that will not be completed.
create or replace function public.close_sales_order(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare d trade_documents%rowtype;
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) or d.doc_type <> 'sales_order' then raise exception 'Order not found'; end if;
  if not public._doc_can(d.org_id, d.doc_type, 'approve') then raise exception 'You do not have permission to close this order'; end if;
  if d.status not in ('approved', 'partial') then raise exception 'Only an open order can be closed'; end if;
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'Give a reason for closing the order'; end if;
  update trade_documents set status = 'closed', cancel_reason = btrim(p_reason) where id = p_id;
end $$;

-- Cancels a quotation, order or invoice. A posted invoice is reversed, not erased:
-- stock is returned at the cost it left at and the accounting entry is reversed.
create or replace function public.cancel_sales_document(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  d trade_documents%rowtype; v_uid uuid := auth.uid(); v_reason text := btrim(coalesce(p_reason, ''));
  m stock_movements%rowtype;
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) then raise exception 'Document not found'; end if;
  if v_reason = '' then raise exception 'Give a reason for cancelling'; end if;
  if d.status = 'cancelled' then raise exception 'This document is already cancelled'; end if;

  if d.doc_type = 'sales_quotation' then
    if d.status = 'converted' then raise exception 'A sales order was raised from this quotation. Cancel that order first.'; end if;
    if d.status not in ('draft', 'sent', 'accepted', 'rejected') then raise exception 'This quotation cannot be cancelled'; end if;
    if not (public._doc_can(d.org_id, d.doc_type, 'edit') or d.created_by = v_uid) then
      raise exception 'You do not have permission to cancel this quotation';
    end if;

  elsif d.doc_type = 'sales_order' then
    if d.status in ('partial', 'invoiced', 'closed') then
      raise exception 'Invoices have been raised on this order. Close it instead of cancelling.';
    end if;
    if d.status not in ('draft', 'pending', 'approved', 'rejected') then raise exception 'This order cannot be cancelled'; end if;
    if not (public._doc_can(d.org_id, d.doc_type, 'approve') or (d.created_by = v_uid and d.status in ('draft', 'rejected'))) then
      raise exception 'You do not have permission to cancel this order';
    end if;
    if exists (
      select 1 from trade_document_lines c join trade_documents cd on cd.id = c.document_id
      where cd.status <> 'cancelled' and c.source_line_id in (select id from trade_document_lines where document_id = p_id)
    ) or exists (select 1 from trade_documents x where x.source_id = p_id and x.status <> 'cancelled') then
      raise exception 'This order already has invoices. Cancel those first.';
    end if;

  elsif d.doc_type = 'sales_invoice' then
    if d.status = 'posted' then
      if not public._doc_can(d.org_id, d.doc_type, 'approve') then raise exception 'You do not have permission to cancel a posted invoice'; end if;
      if exists (select 1 from payment_allocations a where a.document_id = p_id and a.reversed_at is null) then
        raise exception 'This invoice has payments applied to it. Cancel the payments or unapply them first.';
      end if;
      for m in select * from stock_movements where source_type = 'sales_invoice' and source_id = p_id and reversal_of is null and quantity < 0 loop
        perform public._stock_reverse(m.id, current_date, d.number, 'Reversal of ' || d.number);
      end loop;
      if d.voucher_id is not null then perform public._reverse_voucher(d.voucher_id, current_date, v_reason); end if;
    elsif d.status in ('draft', 'pending', 'approved', 'rejected') then
      if not (public._doc_can(d.org_id, d.doc_type, 'approve') or (d.created_by = v_uid and d.status in ('draft', 'rejected'))) then
        raise exception 'You do not have permission to cancel this invoice';
      end if;
    else
      raise exception 'This invoice cannot be cancelled';
    end if;
  else
    raise exception 'This document cannot be cancelled here';
  end if;

  update trade_documents set status = 'cancelled', cancel_reason = v_reason, cancelled_at = now() where id = p_id;
  if d.doc_type = 'sales_order' then perform public._sync_quotation(d.source_id); end if;
  if d.doc_type = 'sales_invoice' then perform public._sync_so_status(d.source_id); end if;
  if d.created_by is not null and d.created_by <> v_uid then
    perform public._notify_user(d.org_id, d.created_by,
      public._doc_label(d.doc_type) || ' ' || d.number || ' was cancelled', v_reason, 'info', d.doc_type, d.id);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Sales invoice posting
--   Dr Accounts receivable            total
--   Cr Sales revenue (or line account) net amounts
--   Cr Output tax payable             tax
--   Dr Cost of goods sold / Cr Inventory  stock lines at average cost
-- Approves the invoice first if it is not approved yet. A customer over
-- the credit limit is refused unless the poster confirms the override.
-- ---------------------------------------------------------------------
create or replace function public.post_sales_invoice(p_id uuid, p_override_credit boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare
  d trade_documents%rowtype; l record; a record; v_party parties%rowtype;
  v_cogs numeric := 0; v_val numeric; v_lines jsonb := '[]'::jsonb; v_voucher uuid;
  v_exposure numeric; v_rev uuid; v_over boolean := false;
begin
  select * into d from trade_documents where id = p_id for update;
  if not found or not public.is_org_member(d.org_id) or d.doc_type <> 'sales_invoice' then raise exception 'Invoice not found'; end if;
  if d.status not in ('draft', 'pending', 'approved') then raise exception 'This invoice cannot be posted'; end if;
  if not public._doc_can(d.org_id, d.doc_type, 'approve') then raise exception 'You do not have permission to approve and post invoices'; end if;
  if d.total <= 0 then raise exception 'The invoice total must be greater than zero'; end if;
  select * into v_party from parties where id = d.party_id;

  -- Credit limit: open invoices less unapplied receipts, plus this invoice.
  if v_party.credit_limit is not null and v_party.credit_limit > 0 then
    v_exposure := public._party_exposure(d.org_id, d.party_id) + d.total;
    if v_exposure > v_party.credit_limit then
      if not coalesce(p_override_credit, false) then
        raise exception 'Credit limit exceeded. % may owe up to %, and this invoice would take them to %.',
          v_party.name, to_char(v_party.credit_limit, 'FM999,999,999,990.00'), to_char(v_exposure, 'FM999,999,999,990.00');
      end if;
      v_over := true;
    end if;
  end if;

  v_rev := public._sys_account(d.org_id, 'sales_revenue');

  for l in select ln.*, p.track_inventory, p.item_type from trade_document_lines ln
           left join products p on p.id = ln.product_id
           where ln.document_id = p_id order by ln.line_no loop
    if l.product_id is not null and l.track_inventory and l.item_type <> 'service' then
      if d.warehouse_id is null then raise exception 'Choose the warehouse the goods are issued from'; end if;
      v_val := public._stock_move(d.org_id, l.product_id, d.warehouse_id, d.doc_date, 'sales_issue', -l.quantity,
                                  null, 'sales_invoice', d.id, l.id, d.number, null);
      v_cogs := v_cogs - v_val;
    end if;
  end loop;

  v_lines := v_lines || jsonb_build_object('account_id', public._sys_account(d.org_id, 'accounts_receivable'),
    'debit', d.total, 'party_id', d.party_id, 'description', 'Invoice ' || d.number || ' - ' || v_party.name);
  for a in
    select coalesce(account_id, v_rev) as acct, sum(net_amount) as amount from trade_document_lines
    where document_id = p_id group by coalesce(account_id, v_rev) having sum(net_amount) > 0
  loop
    v_lines := v_lines || jsonb_build_object('account_id', a.acct, 'credit', a.amount, 'party_id', d.party_id,
      'description', 'Sales ' || d.number);
  end loop;
  if d.tax_total > 0 then
    v_lines := v_lines || jsonb_build_object('account_id', public._sys_account(d.org_id, 'output_tax'),
      'credit', d.tax_total, 'description', 'Output tax on ' || d.number);
  end if;
  if v_cogs > 0 then
    v_lines := v_lines
      || jsonb_build_object('account_id', public._sys_account(d.org_id, 'cogs'), 'debit', v_cogs, 'description', 'Cost of goods sold ' || d.number)
      || jsonb_build_object('account_id', public._sys_account(d.org_id, 'inventory'), 'credit', v_cogs, 'description', 'Stock issued ' || d.number);
  end if;

  v_voucher := public._post_new_voucher(
    d.org_id, 'journal', d.doc_date, 'Sales invoice ' || d.number || ' - ' || v_party.name, d.reference, d.branch_id,
    v_lines, 'sales_invoice', d.id);

  update trade_documents set status = 'posted', posted_by = auth.uid(), posted_at = now(), voucher_id = v_voucher,
    approved_by = coalesce(approved_by, auth.uid()), approved_at = coalesce(approved_at, now()), credit_overridden = v_over
  where id = p_id;

  perform public._sync_so_status(d.source_id);
  perform public._notify_user(d.org_id, d.created_by, 'Invoice ' || d.number || ' is posted', null, 'info', d.doc_type, d.id);
  perform public.notify_members_with_permission(
    d.org_id, 'finance', 'create', 'Invoice ' || d.number || ' is due ' || to_char(d.due_date, 'DD Mon YYYY'),
    v_party.name || ' - total ' || to_char(d.total, 'FM999,999,999,990.00'), 'due', 'sales_invoice', d.id);
end $$;

-- ---------------------------------------------------------------------
-- Opening balances entered as posted invoices and bills. They carry the
-- original date and due date, so they age and are paid like any other
-- document, and they post against Opening balance equity.
-- ---------------------------------------------------------------------
create or replace function public.post_opening_balance(
  p_org uuid, p_kind text, p_party uuid, p_date date, p_due date, p_reference text, p_amount numeric,
  p_notes text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_party parties%rowtype; v_amount numeric := round(coalesce(p_amount, 0), 2);
  v_type text; v_id uuid := gen_random_uuid(); v_number text; v_due date;
  v_ref text := nullif(btrim(coalesce(p_reference, '')), ''); v_voucher uuid; v_lines jsonb; v_equity uuid;
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  if not public.is_org_member(p_org) then raise exception 'Access denied'; end if;
  if p_kind not in ('receivable', 'payable') then raise exception 'Choose receivable or payable'; end if;
  if not public.has_permission(p_org, 'finance', 'create') then
    raise exception 'You do not have permission to enter opening balances';
  end if;
  if v_amount <= 0 then raise exception 'Enter an amount greater than zero'; end if;
  if p_date is null then raise exception 'Choose the date of the original invoice'; end if;

  select * into v_party from parties where id = p_party and org_id = p_org;
  if not found then raise exception 'Party not found'; end if;
  if p_kind = 'receivable' and not v_party.is_customer then raise exception 'Choose a customer'; end if;
  if p_kind = 'payable' and not v_party.is_supplier then raise exception 'Choose a supplier'; end if;

  v_type := case p_kind when 'receivable' then 'sales_invoice' else 'supplier_bill' end;
  v_due := coalesce(p_due, p_date + coalesce(v_party.payment_terms_days, 0));
  if v_due < p_date then raise exception 'The due date cannot be before the document date'; end if;
  if v_type = 'supplier_bill' and v_ref is not null and exists (
    select 1 from trade_documents where org_id = p_org and doc_type = 'supplier_bill' and party_id = p_party
      and status <> 'cancelled' and lower(btrim(reference)) = lower(v_ref)) then
    raise exception 'A bill with the supplier invoice number "%" already exists for this supplier', v_ref;
  end if;

  v_number := public.next_doc_number(p_org, case p_kind when 'receivable' then 'opening_invoice' else 'opening_bill' end);
  insert into trade_documents (id, org_id, doc_type, number, doc_date, due_date, status, party_id, reference, notes,
                               is_opening, created_by)
  values (v_id, p_org, v_type, v_number, p_date, v_due, 'draft', p_party, v_ref,
          nullif(btrim(coalesce(p_notes, '')), ''), true, v_uid);
  insert into trade_document_lines (org_id, document_id, line_no, description, quantity, unit_price, net_amount, line_total)
  values (p_org, v_id, 1, 'Opening balance' || coalesce(' - ' || v_ref, ''), 1, v_amount, v_amount, v_amount);

  v_equity := public._sys_account(p_org, 'opening_balance_equity');
  if p_kind = 'receivable' then
    v_lines := jsonb_build_array(
      jsonb_build_object('account_id', public._sys_account(p_org, 'accounts_receivable'), 'debit', v_amount,
                         'party_id', p_party, 'description', 'Opening receivable ' || v_number),
      jsonb_build_object('account_id', v_equity, 'credit', v_amount, 'description', 'Opening receivable ' || v_number));
  else
    v_lines := jsonb_build_array(
      jsonb_build_object('account_id', v_equity, 'debit', v_amount, 'description', 'Opening payable ' || v_number),
      jsonb_build_object('account_id', public._sys_account(p_org, 'accounts_payable'), 'credit', v_amount,
                         'party_id', p_party, 'description', 'Opening payable ' || v_number));
  end if;
  v_voucher := public._post_new_voucher(p_org, 'journal', p_date, 'Opening balance ' || v_number || ' - ' || v_party.name,
                                        v_ref, null, v_lines, v_type, v_id);

  update trade_documents set status = 'posted', subtotal = v_amount, total = v_amount, voucher_id = v_voucher,
    posted_by = v_uid, posted_at = now(), approved_by = v_uid, approved_at = now()
  where id = v_id;

  -- A balance typed on the profile before opening documents existed is now in the books.
  if p_kind = 'receivable' then
    update parties set opening_receivable = greatest(opening_receivable - v_amount, 0) where id = p_party;
  else
    update parties set opening_payable = greatest(opening_payable - v_amount, 0) where id = p_party;
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Payments
-- ---------------------------------------------------------------------

-- Locks the open documents a payment is applied to and checks each amount against what is still owed.
create or replace function public._check_allocations(
  p_org uuid, p_kind text, p_party uuid, p_exclude_payment uuid, p_allocations jsonb
) returns numeric language plpgsql security definer set search_path = public as $$
declare r record; d trade_documents%rowtype; v_open numeric; v_total numeric := 0; v_type text;
begin
  v_type := case p_kind when 'receipt' then 'sales_invoice' else 'supplier_bill' end;
  if p_allocations is null or jsonb_typeof(p_allocations) <> 'array' then return 0; end if;
  if (select count(*) <> count(distinct x.document_id) from jsonb_to_recordset(p_allocations) as x(document_id uuid, amount numeric)) then
    raise exception 'Each document can appear only once';
  end if;
  for r in select * from jsonb_to_recordset(p_allocations) as x(document_id uuid, amount numeric) order by x.document_id loop
    if r.document_id is null or coalesce(r.amount, 0) <= 0 then raise exception 'Enter an amount greater than zero for each document'; end if;
    select * into d from trade_documents where id = r.document_id and org_id = p_org for update;
    if not found or d.doc_type <> v_type or d.status <> 'posted' then
      raise exception 'Choose a posted % to pay', case p_kind when 'receipt' then 'invoice' else 'bill' end;
    end if;
    if d.party_id is distinct from p_party then raise exception '% belongs to a different %', d.number, case p_kind when 'receipt' then 'customer' else 'supplier' end; end if;
    select d.total - coalesce(sum(a.amount), 0) into v_open from payment_allocations a
    where a.document_id = d.id and a.reversed_at is null;
    if round(r.amount, 2) > v_open then
      raise exception '% has only % still to pay', d.number, to_char(v_open, 'FM999,999,999,990.00');
    end if;
    v_total := v_total + round(r.amount, 2);
  end loop;
  return v_total;
end $$;

-- Records money received from a customer (receipt) or paid to a supplier (payment) and posts it.
-- Whatever is not allocated to a document stays as an advance on the party.
create or replace function public.record_payment(
  p_id uuid, p_org uuid, p_kind text, p_party uuid, p_date date, p_fin uuid, p_method uuid, p_amount numeric,
  p_reference text, p_notes text, p_allocations jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_amount numeric := round(coalesce(p_amount, 0), 2); v_party parties%rowtype;
  f financial_accounts%rowtype; v_alloc numeric; v_adv numeric; v_number text; v_voucher uuid; v_lines jsonb := '[]'::jsonb;
  v_id uuid := coalesce(p_id, gen_random_uuid()); v_ctrl uuid; v_advacct uuid; r record;
  v_ref text := nullif(btrim(coalesce(p_reference, '')), '');
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  if not public.is_org_member(p_org) then raise exception 'Access denied'; end if;
  if p_kind not in ('receipt', 'payment') then raise exception 'Unknown payment type'; end if;
  if not public._pay_can(p_org, p_kind, 'create') then
    raise exception 'You do not have permission to record %', case p_kind when 'receipt' then 'receipts' else 'payments' end;
  end if;
  if v_amount <= 0 then raise exception 'Enter an amount greater than zero'; end if;
  if p_date is null then raise exception 'Choose the payment date'; end if;
  if exists (select 1 from payments where id = v_id) then raise exception 'This payment has already been recorded'; end if;

  select * into v_party from parties where id = p_party and org_id = p_org;
  if not found then raise exception 'Choose a %', case p_kind when 'receipt' then 'customer' else 'supplier' end; end if;
  if p_kind = 'receipt' and not v_party.is_customer then raise exception 'Choose a customer'; end if;
  if p_kind = 'payment' and not v_party.is_supplier then raise exception 'Choose a supplier'; end if;
  select * into f from financial_accounts where id = p_fin and org_id = p_org and is_active;
  if not found then raise exception 'Choose an active cash or bank account'; end if;
  if p_method is not null and not exists (select 1 from lookups where id = p_method and org_id = p_org and kind = 'payment_method') then
    raise exception 'Choose a valid payment method';
  end if;

  v_alloc := public._check_allocations(p_org, p_kind, p_party, null, p_allocations);
  if v_alloc > v_amount then
    raise exception 'The amounts applied (%) are more than the payment (%)',
      to_char(v_alloc, 'FM999,999,999,990.00'), to_char(v_amount, 'FM999,999,999,990.00');
  end if;
  v_adv := v_amount - v_alloc;

  v_number := public.next_doc_number(p_org, case p_kind when 'receipt' then 'customer_receipt' else 'supplier_payment' end);
  v_ctrl := public._sys_account(p_org, case p_kind when 'receipt' then 'accounts_receivable' else 'accounts_payable' end);
  v_advacct := public._sys_account(p_org, case p_kind when 'receipt' then 'customer_advance' else 'supplier_advance' end);

  if p_kind = 'receipt' then
    v_lines := v_lines || jsonb_build_object('account_id', f.account_id, 'debit', v_amount, 'description', 'Received ' || v_number || ' from ' || v_party.name);
    if v_alloc > 0 then v_lines := v_lines || jsonb_build_object('account_id', v_ctrl, 'credit', v_alloc, 'party_id', p_party, 'description', 'Applied to invoices'); end if;
    if v_adv > 0 then v_lines := v_lines || jsonb_build_object('account_id', v_advacct, 'credit', v_adv, 'party_id', p_party, 'description', 'Advance received'); end if;
  else
    if v_alloc > 0 then v_lines := v_lines || jsonb_build_object('account_id', v_ctrl, 'debit', v_alloc, 'party_id', p_party, 'description', 'Applied to bills'); end if;
    if v_adv > 0 then v_lines := v_lines || jsonb_build_object('account_id', v_advacct, 'debit', v_adv, 'party_id', p_party, 'description', 'Advance paid'); end if;
    v_lines := v_lines || jsonb_build_object('account_id', f.account_id, 'credit', v_amount, 'description', 'Paid ' || v_number || ' to ' || v_party.name);
  end if;

  v_voucher := public._post_new_voucher(
    p_org, case p_kind when 'receipt' then 'receipt' else 'payment' end, p_date,
    case p_kind when 'receipt' then 'Receipt ' else 'Payment ' end || v_number || ' - ' || v_party.name, v_ref, null,
    v_lines, case p_kind when 'receipt' then 'customer_receipt' else 'supplier_payment' end, v_id);

  insert into payments (id, org_id, kind, number, pay_date, party_id, financial_account_id, method_id, amount, reference,
                        notes, status, voucher_id, created_by)
  values (v_id, p_org, p_kind, v_number, p_date, p_party, p_fin, p_method, v_amount, v_ref,
          nullif(btrim(coalesce(p_notes, '')), ''), 'posted', v_voucher, v_uid);

  if p_allocations is not null and jsonb_typeof(p_allocations) = 'array' then
    for r in select * from jsonb_to_recordset(p_allocations) as x(document_id uuid, amount numeric) loop
      insert into payment_allocations (org_id, payment_id, document_id, amount, alloc_date)
      values (p_org, v_id, r.document_id, round(r.amount, 2), p_date);
    end loop;
  end if;
  return v_id;
end $$;

-- Applies part of an advance (money already received or paid) to a document.
create or replace function public.apply_advance(p_payment uuid, p_document uuid, p_amount numeric, p_date date default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  p payments%rowtype; d trade_documents%rowtype; v_amount numeric := round(coalesce(p_amount, 0), 2);
  v_free numeric; v_open numeric; v_date date := coalesce(p_date, current_date); v_voucher uuid; v_lines jsonb;
  v_ctrl uuid; v_advacct uuid; v_alloc uuid := gen_random_uuid(); v_type text;
begin
  select * into p from payments where id = p_payment for update;
  if not found or not public.is_org_member(p.org_id) then raise exception 'Payment not found'; end if;
  if not public._pay_can(p.org_id, p.kind, 'create') then raise exception 'You do not have permission to apply payments'; end if;
  if p.status <> 'posted' then raise exception 'A cancelled payment cannot be applied'; end if;
  if v_amount <= 0 then raise exception 'Enter an amount greater than zero'; end if;

  v_type := case p.kind when 'receipt' then 'sales_invoice' else 'supplier_bill' end;
  select * into d from trade_documents where id = p_document and org_id = p.org_id for update;
  if not found or d.status <> 'posted' or d.doc_type <> v_type then
    raise exception 'Choose a posted % to apply it to', case p.kind when 'receipt' then 'invoice' else 'bill' end;
  end if;
  if d.party_id is distinct from p.party_id then raise exception 'The document belongs to a different party'; end if;

  select p.amount - coalesce(sum(a.amount), 0) into v_free from payment_allocations a where a.payment_id = p.id and a.reversed_at is null;
  if v_amount > v_free then raise exception 'Only % of this payment is unapplied', to_char(v_free, 'FM999,999,999,990.00'); end if;
  select d.total - coalesce(sum(a.amount), 0) into v_open from payment_allocations a where a.document_id = d.id and a.reversed_at is null;
  if v_amount > v_open then raise exception '% has only % still to pay', d.number, to_char(v_open, 'FM999,999,999,990.00'); end if;

  v_ctrl := public._sys_account(p.org_id, case p.kind when 'receipt' then 'accounts_receivable' else 'accounts_payable' end);
  v_advacct := public._sys_account(p.org_id, case p.kind when 'receipt' then 'customer_advance' else 'supplier_advance' end);
  if p.kind = 'receipt' then
    v_lines := jsonb_build_array(
      jsonb_build_object('account_id', v_advacct, 'debit', v_amount, 'party_id', p.party_id, 'description', 'Advance ' || p.number || ' applied to ' || d.number),
      jsonb_build_object('account_id', v_ctrl, 'credit', v_amount, 'party_id', p.party_id, 'description', 'Advance ' || p.number || ' applied to ' || d.number));
  else
    v_lines := jsonb_build_array(
      jsonb_build_object('account_id', v_ctrl, 'debit', v_amount, 'party_id', p.party_id, 'description', 'Advance ' || p.number || ' applied to ' || d.number),
      jsonb_build_object('account_id', v_advacct, 'credit', v_amount, 'party_id', p.party_id, 'description', 'Advance ' || p.number || ' applied to ' || d.number));
  end if;
  v_voucher := public._post_new_voucher(p.org_id, 'journal', v_date, 'Advance ' || p.number || ' applied to ' || d.number, null, null,
                                        v_lines, 'payment_allocation', v_alloc);
  insert into payment_allocations (id, org_id, payment_id, document_id, amount, alloc_date, voucher_id)
  values (v_alloc, p.org_id, p.id, d.id, v_amount, v_date, v_voucher);
end $$;

-- Posts the entry that returns an allocated amount to the party's advance, and marks the allocation reversed.
create or replace function public._unapply(p_alloc uuid, p_post_entry boolean, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  a payment_allocations%rowtype; p payments%rowtype; d trade_documents%rowtype; v_lines jsonb;
  v_ctrl uuid; v_advacct uuid; v_reason text := coalesce(nullif(btrim(p_reason), ''), 'Unapplied');
begin
  select * into a from payment_allocations where id = p_alloc for update;
  if not found or a.reversed_at is not null then raise exception 'This allocation has already been removed'; end if;
  select * into p from payments where id = a.payment_id;
  select * into d from trade_documents where id = a.document_id;
  if p_post_entry then
    v_ctrl := public._sys_account(p.org_id, case p.kind when 'receipt' then 'accounts_receivable' else 'accounts_payable' end);
    v_advacct := public._sys_account(p.org_id, case p.kind when 'receipt' then 'customer_advance' else 'supplier_advance' end);
    if p.kind = 'receipt' then
      v_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_ctrl, 'debit', a.amount, 'party_id', p.party_id, 'description', 'Unapplied ' || p.number || ' from ' || d.number),
        jsonb_build_object('account_id', v_advacct, 'credit', a.amount, 'party_id', p.party_id, 'description', 'Unapplied ' || p.number || ' from ' || d.number));
    else
      v_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_advacct, 'debit', a.amount, 'party_id', p.party_id, 'description', 'Unapplied ' || p.number || ' from ' || d.number),
        jsonb_build_object('account_id', v_ctrl, 'credit', a.amount, 'party_id', p.party_id, 'description', 'Unapplied ' || p.number || ' from ' || d.number));
    end if;
    perform public._post_new_voucher(p.org_id, 'journal', current_date, 'Unapplied ' || p.number || ' from ' || d.number || ': ' || v_reason,
                                     null, null, v_lines, 'payment_unapply', a.id);
  end if;
  update payment_allocations set reversed_at = now() where id = p_alloc;
end $$;

-- Takes an amount off a document and returns it to the party's advance.
create or replace function public.unapply_allocation(p_alloc uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare a payment_allocations%rowtype; p payments%rowtype;
begin
  select * into a from payment_allocations where id = p_alloc;
  if not found or not public.is_org_member(a.org_id) then raise exception 'Allocation not found'; end if;
  select * into p from payments where id = a.payment_id for update;
  if not public._pay_can(p.org_id, p.kind, 'approve') then raise exception 'You do not have permission to unapply payments'; end if;
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'Give a reason'; end if;
  perform public._unapply(p_alloc, true, p_reason);
end $$;

-- Reverses a payment: the money entry is reversed and every document it paid is open again.
-- When the payment still stands exactly as it was recorded, its entry is mirrored. When allocations
-- were changed afterwards, every active allocation is first returned to the advance and the whole
-- amount is then taken back out of the advance, so the ledgers cannot drift.
create or replace function public.cancel_payment(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  p payments%rowtype; a payment_allocations%rowtype; f financial_accounts%rowtype; v_orig vouchers%rowtype;
  v_reason text := btrim(coalesce(p_reason, '')); v_simple boolean; v_new uuid; v_lines jsonb; v_advacct uuid;
begin
  select * into p from payments where id = p_id for update;
  if not found or not public.is_org_member(p.org_id) then raise exception 'Payment not found'; end if;
  if not public._pay_can(p.org_id, p.kind, 'approve') then raise exception 'You do not have permission to cancel payments'; end if;
  if p.status = 'cancelled' then raise exception 'This payment is already cancelled'; end if;
  if v_reason = '' then raise exception 'Give a reason for cancelling'; end if;

  v_simple := not exists (select 1 from payment_allocations where payment_id = p_id and (voucher_id is not null or reversed_at is not null));
  if v_simple then
    for a in select * from payment_allocations where payment_id = p_id and reversed_at is null loop
      perform public._unapply(a.id, false, 'Payment ' || p.number || ' cancelled');
    end loop;
    if p.voucher_id is not null then perform public._reverse_voucher(p.voucher_id, current_date, v_reason); end if;
  else
    for a in select * from payment_allocations where payment_id = p_id and reversed_at is null order by created_at loop
      perform public._unapply(a.id, true, 'Payment ' || p.number || ' cancelled');
    end loop;
    select * into f from financial_accounts where id = p.financial_account_id;
    v_advacct := public._sys_account(p.org_id, case p.kind when 'receipt' then 'customer_advance' else 'supplier_advance' end);
    if p.kind = 'receipt' then
      v_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_advacct, 'debit', p.amount, 'party_id', p.party_id, 'description', 'Reversal of ' || p.number),
        jsonb_build_object('account_id', f.account_id, 'credit', p.amount, 'description', 'Reversal of ' || p.number));
    else
      v_lines := jsonb_build_array(
        jsonb_build_object('account_id', f.account_id, 'debit', p.amount, 'description', 'Reversal of ' || p.number),
        jsonb_build_object('account_id', v_advacct, 'credit', p.amount, 'party_id', p.party_id, 'description', 'Reversal of ' || p.number));
    end if;
    select * into v_orig from vouchers where id = p.voucher_id;
    v_new := public._post_new_voucher(p.org_id, v_orig.voucher_type, current_date,
      'Reversal of ' || v_orig.voucher_no || ': ' || v_reason, v_orig.reference, v_orig.branch_id, v_lines,
      v_orig.source_type, v_orig.source_id, v_orig.id);
    update vouchers set reversed_by = v_new where id = v_orig.id;
  end if;
  update payments set status = 'cancelled', cancel_reason = v_reason, cancelled_at = now() where id = p_id;
end $$;

-- ---------------------------------------------------------------------
-- Read functions: aging, statements, dues
-- They run with the caller's rights, so row level security decides what
-- each person sees.
-- ---------------------------------------------------------------------

-- Open invoices (receivable) or bills (payable) as of a date, with days past due and aging bucket.
-- Days past due is counted from the due date; zero or less means not yet due.
create or replace function public.aging_documents(
  p_org uuid, p_kind text, p_as_of date default current_date, p_party uuid default null
) returns table (
  document_id uuid, doc_type text, party_id uuid, party_name text, number text, reference text, doc_date date,
  due_date date, total numeric, paid numeric, balance numeric, days_past_due int, bucket text, is_opening boolean
) language sql stable as $$
  select t.id, t.doc_type, t.party_id, t.name, t.number, t.reference, t.doc_date, t.due_date, t.total, t.paid, t.balance,
         t.days_past_due,
         case when t.days_past_due <= 0 then 'current' when t.days_past_due <= 30 then 'd1_30'
              when t.days_past_due <= 60 then 'd31_60' when t.days_past_due <= 90 then 'd61_90'
              else 'over_90' end,
         t.is_opening
  from (
    select d.id, d.doc_type, d.party_id, pa.name, d.number, d.reference, d.doc_date,
           coalesce(d.due_date, d.doc_date) as due_date, d.total, coalesce(x.paid, 0)::numeric as paid,
           (d.total - coalesce(x.paid, 0))::numeric as balance,
           (coalesce(p_as_of, current_date) - coalesce(d.due_date, d.doc_date))::int as days_past_due, d.is_opening
    from trade_documents d
    join parties pa on pa.id = d.party_id
    left join lateral (
      select sum(a.amount) as paid from payment_allocations a
      where a.document_id = d.id and a.reversed_at is null and a.alloc_date <= coalesce(p_as_of, current_date)
    ) x on true
    where d.org_id = p_org and d.status = 'posted'
      and p_kind in ('receivable', 'payable')
      and d.doc_type = case p_kind when 'receivable' then 'sales_invoice' else 'supplier_bill' end
      and d.doc_date <= coalesce(p_as_of, current_date)
      and (p_party is null or d.party_id = p_party)
      and d.total - coalesce(x.paid, 0) > 0
  ) t
  order by t.due_date, t.number;
$$;

-- Dues by customer or supplier in the aging buckets, with unapplied advances.
create or replace function public.party_aging(
  p_org uuid, p_kind text, p_as_of date default current_date, p_party uuid default null
) returns table (
  party_id uuid, party_name text, party_code text, credit_limit numeric, current_amt numeric, d1_30 numeric,
  d31_60 numeric, d61_90 numeric, over_90 numeric, total_due numeric, overdue_total numeric, advance numeric,
  net_due numeric, open_count int, oldest_days int
) language sql stable as $$
  with items as (select * from public.aging_documents(p_org, p_kind, p_as_of, p_party)),
  agg as (
    select i.party_id,
           sum(i.balance) filter (where i.bucket = 'current') as cur,
           sum(i.balance) filter (where i.bucket = 'd1_30') as b1,
           sum(i.balance) filter (where i.bucket = 'd31_60') as b2,
           sum(i.balance) filter (where i.bucket = 'd61_90') as b3,
           sum(i.balance) filter (where i.bucket = 'over_90') as b4,
           sum(i.balance) as total,
           sum(i.balance) filter (where i.days_past_due > 0) as overdue,
           count(*) as cnt, max(i.days_past_due) as oldest
    from items i group by i.party_id
  ),
  adv as (
    select pm.party_id, sum(pm.amount - coalesce(al.amt, 0)) as advance
    from payments pm
    left join lateral (
      select sum(a.amount) as amt from payment_allocations a
      where a.payment_id = pm.id and a.reversed_at is null and a.alloc_date <= coalesce(p_as_of, current_date)
    ) al on true
    where pm.org_id = p_org and pm.status = 'posted' and pm.pay_date <= coalesce(p_as_of, current_date)
      and pm.kind = case p_kind when 'receivable' then 'receipt' else 'payment' end
      and (p_party is null or pm.party_id = p_party)
    group by pm.party_id
    having sum(pm.amount - coalesce(al.amt, 0)) > 0
  )
  select pa.id, pa.name, pa.code, pa.credit_limit,
         coalesce(agg.cur, 0), coalesce(agg.b1, 0), coalesce(agg.b2, 0), coalesce(agg.b3, 0), coalesce(agg.b4, 0),
         coalesce(agg.total, 0), coalesce(agg.overdue, 0), coalesce(adv.advance, 0),
         coalesce(agg.total, 0) - coalesce(adv.advance, 0), coalesce(agg.cnt, 0)::int, coalesce(agg.oldest, 0)::int
  from agg full join adv on adv.party_id = agg.party_id
  join parties pa on pa.id = coalesce(agg.party_id, adv.party_id)
  order by coalesce(agg.total, 0) desc, pa.name;
$$;

-- Account statement of one customer or supplier: documents and payments with a running balance.
-- The balance is what the party owes you (customer) or what you owe them (supplier).
create or replace function public.party_statement(
  p_org uuid, p_party uuid, p_role text, p_from date default null, p_to date default null
) returns table (
  row_type text, entry_date date, doc_id uuid, doc_type text, number text, reference text, due_date date,
  charge numeric, payment numeric, balance numeric, is_opening boolean
) language sql stable as $$
  with ev as (
    select d.doc_date as entry_date, d.created_at, d.id as doc_id, d.doc_type, d.number, d.reference,
           d.due_date, d.total as charge, 0::numeric as payment, d.is_opening
    from trade_documents d
    where d.org_id = p_org and d.party_id = p_party and d.status = 'posted'
      and d.doc_type = case p_role when 'customer' then 'sales_invoice' else 'supplier_bill' end
    union all
    select pm.pay_date, pm.created_at, pm.id, case pm.kind when 'receipt' then 'customer_receipt' else 'supplier_payment' end,
           pm.number, pm.reference, null::date, 0::numeric, pm.amount, false
    from payments pm
    where pm.org_id = p_org and pm.party_id = p_party and pm.status = 'posted'
      and pm.kind = case p_role when 'customer' then 'receipt' else 'payment' end
  ),
  opening as (
    select coalesce(sum(charge - payment), 0) as amt from ev where p_from is not null and entry_date < p_from
  ),
  body as (
    select ev.*, (select amt from opening) + sum(ev.charge - ev.payment) over (order by ev.entry_date, ev.created_at, ev.doc_id) as run
    from ev
    where (p_from is null or ev.entry_date >= p_from) and (p_to is null or ev.entry_date <= p_to)
  )
  select u.row_type, u.entry_date, u.doc_id, u.doc_type, u.number, u.reference, u.due_date, u.charge, u.payment, u.balance, u.is_opening
  from (
    select 0 as k, 'opening'::text as row_type, p_from as entry_date, null::timestamptz as created_at, null::uuid as doc_id,
           null::text as doc_type, null::text as number, null::text as reference, null::date as due_date,
           0::numeric as charge, 0::numeric as payment, o.amt as balance, false as is_opening
    from opening o where p_from is not null
    union all
    select 1, case when b.doc_type in ('customer_receipt', 'supplier_payment') then 'payment' else 'document' end,
           b.entry_date, b.created_at, b.doc_id, b.doc_type, b.number, b.reference, b.due_date, b.charge, b.payment, b.run, b.is_opening
    from body b
  ) u
  order by u.k, u.entry_date, u.created_at, u.doc_id;
$$;

-- Headline figures for a customer or supplier profile.
create or replace function public.party_summary(p_org uuid, p_party uuid)
returns table (
  receivable_open numeric, receivable_overdue numeric, receivable_advance numeric,
  payable_open numeric, payable_overdue numeric, payable_advance numeric,
  credit_limit numeric, available_credit numeric,
  last_invoice_date date, last_receipt_date date, last_bill_date date, last_payment_date date
) language sql stable as $$
  with docs as (
    select b.doc_type, b.balance, b.days_overdue, b.doc_date from document_balances b
    where b.org_id = p_org and b.party_id = p_party and b.balance > 0
  ),
  allpay as (
    select x.kind, x.unallocated, x.pay_date from payment_balances x
    where x.org_id = p_org and x.party_id = p_party and x.status = 'posted'
  ),
  last_docs as (
    select max(d.doc_date) filter (where d.doc_type = 'sales_invoice') as li,
           max(d.doc_date) filter (where d.doc_type = 'supplier_bill') as lb
    from trade_documents d where d.org_id = p_org and d.party_id = p_party and d.status = 'posted'
  )
  select
    coalesce((select sum(balance) from docs where doc_type = 'sales_invoice'), 0),
    coalesce((select sum(balance) from docs where doc_type = 'sales_invoice' and days_overdue > 0), 0),
    coalesce((select sum(unallocated) from allpay where kind = 'receipt'), 0),
    coalesce((select sum(balance) from docs where doc_type = 'supplier_bill'), 0),
    coalesce((select sum(balance) from docs where doc_type = 'supplier_bill' and days_overdue > 0), 0),
    coalesce((select sum(unallocated) from allpay where kind = 'payment'), 0),
    pa.credit_limit,
    case when pa.credit_limit is null or pa.credit_limit = 0 then null
         else pa.credit_limit - (coalesce((select sum(balance) from docs where doc_type = 'sales_invoice'), 0)
                                 - coalesce((select sum(unallocated) from allpay where kind = 'receipt'), 0)) end,
    (select li from last_docs), (select max(pay_date) from allpay where kind = 'receipt'),
    (select lb from last_docs), (select max(pay_date) from allpay where kind = 'payment')
  from parties pa where pa.id = p_party and pa.org_id = p_org;
$$;

-- Ordered and invoiced quantities of each line of a sales order. Committed counts every live
-- invoice, drafts included, and is what the invoice form can still be raised for.
create or replace function public.sales_order_progress(p_doc uuid, p_exclude uuid default null)
returns table (line_id uuid, ordered_qty numeric, invoiced_qty numeric, committed_qty numeric)
language sql stable as $$
  select l.id, l.quantity,
    coalesce((select sum(g.quantity) from trade_document_lines g join trade_documents gd on gd.id = g.document_id
              where g.source_line_id = l.id and gd.doc_type = 'sales_invoice' and gd.status = 'posted'), 0),
    coalesce((select sum(g.quantity) from trade_document_lines g join trade_documents gd on gd.id = g.document_id
              where g.source_line_id = l.id and gd.doc_type = 'sales_invoice' and gd.status <> 'cancelled'
                and (p_exclude is null or gd.id <> p_exclude)), 0)
  from trade_document_lines l
  where l.document_id = p_doc
  order by l.line_no;
$$;

-- Compares the ledger control accounts with the open documents and advances behind them.
-- A difference means someone posted a manual journal straight to a control account.
create or replace function public.aging_control_check(p_org uuid, p_as_of date default current_date)
returns table (
  side text, ledger_open numeric, documents_open numeric, ledger_advance numeric, advances_open numeric
) language plpgsql stable security definer set search_path = public as $$
declare v_as_of date := coalesce(p_as_of, current_date);
begin
  if not public.has_permission(p_org, 'finance', 'view') then return; end if;
  return query
  select 'receivable'::text,
    coalesce((select sum(l.debit - l.credit) from voucher_lines l join vouchers v on v.id = l.voucher_id join accounts a on a.id = l.account_id
              where a.org_id = p_org and a.system_key = 'accounts_receivable' and v.status = 'posted' and v.voucher_date <= v_as_of), 0),
    coalesce((select sum(t.balance) from public.aging_documents(p_org, 'receivable', v_as_of, null) t), 0),
    coalesce((select sum(l.credit - l.debit) from voucher_lines l join vouchers v on v.id = l.voucher_id join accounts a on a.id = l.account_id
              where a.org_id = p_org and a.system_key = 'customer_advance' and v.status = 'posted' and v.voucher_date <= v_as_of), 0),
    coalesce((select sum(t.advance) from public.party_aging(p_org, 'receivable', v_as_of, null) t), 0)
  union all
  select 'payable'::text,
    coalesce((select sum(l.credit - l.debit) from voucher_lines l join vouchers v on v.id = l.voucher_id join accounts a on a.id = l.account_id
              where a.org_id = p_org and a.system_key = 'accounts_payable' and v.status = 'posted' and v.voucher_date <= v_as_of), 0),
    coalesce((select sum(t.balance) from public.aging_documents(p_org, 'payable', v_as_of, null) t), 0),
    coalesce((select sum(l.debit - l.credit) from voucher_lines l join vouchers v on v.id = l.voucher_id join accounts a on a.id = l.account_id
              where a.org_id = p_org and a.system_key = 'supplier_advance' and v.status = 'posted' and v.voucher_date <= v_as_of), 0),
    coalesce((select sum(t.advance) from public.party_aging(p_org, 'payable', v_as_of, null) t), 0);
end $$;

-- ---------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
           where p.pronamespace = 'public'::regnamespace
             and p.proname in ('save_sales_document', 'mark_quotation_sent', 'set_quotation_outcome', 'reopen_quotation',
                               'submit_sales_document', 'approve_sales_document', 'reject_sales_document',
                               'discard_sales_document', 'close_sales_order', 'cancel_sales_document',
                               'post_sales_invoice', 'post_opening_balance', 'record_payment', 'apply_advance',
                               'unapply_allocation', 'cancel_payment', 'aging_documents', 'party_aging',
                               'party_statement', 'party_summary', 'sales_order_progress', 'aging_control_check')
  loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;

  for f in select p.oid::regprocedure from pg_proc p
           where p.pronamespace = 'public'::regnamespace
             and p.proname in ('seed_sales_defaults', 'trg_seed_org_sales', '_pay_can', '_party_exposure', '_stock_reverse',
                               '_sync_quotation', '_sync_so_status', '_check_allocations', '_unapply')
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
    perform public.seed_sales_defaults(o.id);
  end loop;
end $$;
