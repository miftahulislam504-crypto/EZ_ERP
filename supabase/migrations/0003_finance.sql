-- =====================================================================
-- EZ ERP - Migration 0003: Finance core
-- Chart of accounts, cash and bank accounts, vouchers (double entry),
-- income and expense with approval, ledger functions.
-- Requires 0001_core.sql and 0002_masters.sql.
--
-- Design rules
--  * Posted vouchers are immutable. Mistakes are fixed by reversal.
--  * Money moves only through the SECURITY DEFINER functions below, which
--    check permissions explicitly. Tables have no direct write policies for
--    vouchers, lines, expenses or financial accounts.
--  * Balances and ledgers are computed from posted voucher lines.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Chart of accounts
-- ---------------------------------------------------------------------
create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  code text not null,
  name text not null,
  account_type text not null check (account_type in ('asset', 'liability', 'equity', 'income', 'expense')),
  parent_id uuid references public.accounts(id) on delete restrict,
  is_group boolean not null default false,
  is_system boolean not null default false,
  system_key text,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, code)
);
create unique index accounts_system_key_unique on public.accounts(org_id, system_key) where system_key is not null;
create index accounts_parent_idx on public.accounts(parent_id);
create trigger accounts_updated before update on public.accounts
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- Vouchers and lines
-- ---------------------------------------------------------------------
create table public.vouchers (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  voucher_type text not null
    check (voucher_type in ('journal', 'payment', 'receipt', 'contra', 'debit_note', 'credit_note')),
  voucher_no text not null,
  voucher_date date not null default current_date,
  status text not null default 'draft'
    check (status in ('draft', 'pending', 'approved', 'rejected', 'posted')),
  narration text,
  reference text,
  branch_id uuid references public.branches(id) on delete set null,
  total_amount numeric(18,2) not null default 0,
  source_type text,
  source_id uuid,
  reversal_of uuid references public.vouchers(id) on delete restrict,
  reversed_by uuid references public.vouchers(id) on delete set null,
  rejection_reason text,
  created_by uuid references public.profiles(id) on delete set null,
  submitted_at timestamptz,
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  posted_by uuid references public.profiles(id) on delete set null,
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, voucher_no)
);
create index vouchers_org_date_idx on public.vouchers(org_id, voucher_date desc);
create index vouchers_source_idx on public.vouchers(source_type, source_id);
create trigger vouchers_updated before update on public.vouchers
  for each row execute function public.set_updated_at();

create table public.voucher_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  voucher_id uuid not null references public.vouchers(id) on delete cascade,
  line_no int not null,
  account_id uuid not null references public.accounts(id),
  party_id uuid references public.parties(id) on delete set null,
  description text,
  debit numeric(18,2) not null default 0 check (debit >= 0),
  credit numeric(18,2) not null default 0 check (credit >= 0),
  check ((debit > 0 and credit = 0) or (credit > 0 and debit = 0))
);
create index voucher_lines_account_idx on public.voucher_lines(org_id, account_id);
create index voucher_lines_voucher_idx on public.voucher_lines(voucher_id);
create index voucher_lines_party_idx on public.voucher_lines(org_id, party_id) where party_id is not null;

-- ---------------------------------------------------------------------
-- Cash and bank accounts (each wraps one ledger account)
-- ---------------------------------------------------------------------
create table public.financial_accounts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  kind text not null check (kind in ('cash', 'bank', 'mobile_wallet')),
  name text not null,
  account_id uuid not null unique references public.accounts(id) on delete restrict,
  bank_name text,
  branch_name text,
  account_number text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, name)
);
create trigger financial_accounts_updated before update on public.financial_accounts
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- Income and expense entries
-- ---------------------------------------------------------------------
create table public.income_expenses (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  kind text not null check (kind in ('income', 'expense')),
  number text not null,
  txn_date date not null default current_date,
  account_id uuid not null references public.accounts(id),
  amount numeric(18,2) not null check (amount > 0),
  payee text,
  party_id uuid references public.parties(id) on delete set null,
  description text,
  reference text,
  branch_id uuid references public.branches(id) on delete set null,
  department_id uuid references public.departments(id) on delete set null,
  financial_account_id uuid references public.financial_accounts(id),
  status text not null default 'draft'
    check (status in ('draft', 'pending', 'approved', 'rejected', 'paid', 'received', 'cancelled')),
  requested_by uuid references public.profiles(id) on delete set null,
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  rejection_reason text,
  voucher_id uuid references public.vouchers(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, number)
);
create index income_expenses_org_idx on public.income_expenses(org_id, txn_date desc);
create trigger income_expenses_updated before update on public.income_expenses
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- Integrity triggers
-- ---------------------------------------------------------------------
create or replace function public.accounts_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_parent accounts%rowtype;
begin
  if new.parent_id is not null then
    if new.parent_id = new.id then raise exception 'An account cannot be its own parent'; end if;
    select * into v_parent from accounts where id = new.parent_id;
    if not found or v_parent.org_id <> new.org_id then raise exception 'Parent account not found'; end if;
    if not v_parent.is_group then raise exception 'The parent must be a group account'; end if;
    if v_parent.account_type <> new.account_type then
      raise exception 'An account must have the same type as its parent';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    if old.is_system and (new.account_type <> old.account_type or new.is_group <> old.is_group
                          or new.system_key is distinct from old.system_key) then
      raise exception 'System accounts cannot change type or purpose';
    end if;
    if (new.account_type <> old.account_type or new.is_group <> old.is_group)
       and exists (select 1 from voucher_lines where account_id = old.id) then
      raise exception 'This account already has transactions, so its type cannot change';
    end if;
    if old.is_active and not new.is_active and exists (
         select 1 from accounts c where c.parent_id = old.id and c.is_active) then
      raise exception 'Archive the sub-accounts first';
    end if;
  end if;
  return new;
end $$;
create trigger accounts_guard before insert or update on public.accounts
  for each row execute function public.accounts_guard();

create or replace function public.vouchers_guard()
returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    if old.status not in ('draft', 'rejected') then
      raise exception 'Only draft or rejected vouchers can be deleted';
    end if;
    return old;
  end if;
  if old.status = 'posted' and
     (to_jsonb(new) - 'reversed_by' - 'updated_at') is distinct from (to_jsonb(old) - 'reversed_by' - 'updated_at') then
    raise exception 'Posted vouchers cannot be changed. Reverse the voucher instead.';
  end if;
  return new;
end $$;
create trigger vouchers_guard before update or delete on public.vouchers
  for each row execute function public.vouchers_guard();

create or replace function public.voucher_lines_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  select status into v_status from vouchers where id = case when tg_op = 'DELETE' then old.voucher_id else new.voucher_id end;
  if not found then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;
  if v_status not in ('draft', 'rejected') then
    raise exception 'Lines can only change while the voucher is a draft or rejected';
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end $$;
create trigger voucher_lines_guard before insert or update or delete on public.voucher_lines
  for each row execute function public.voucher_lines_guard();

-- ---------------------------------------------------------------------
-- Internal helpers (not callable from the app)
-- ---------------------------------------------------------------------
create or replace function public._notify_user(
  p_org uuid, p_user uuid, p_title text, p_body text, p_kind text, p_etype text, p_eid uuid
) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_user is null or p_user = auth.uid() then return; end if;
  insert into notifications (org_id, user_id, title, body, kind, entity_type, entity_id)
  values (p_org, p_user, p_title, p_body, p_kind, p_etype, p_eid);
end $$;

-- Validates voucher lines and returns the voucher total.
create or replace function public._validate_voucher_lines(p_org uuid, p_lines jsonb)
returns numeric language plpgsql security definer set search_path = public as $$
declare v_debit numeric := 0; v_credit numeric := 0;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then
    raise exception 'A voucher needs at least two lines';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_lines) x
    where not (
      (coalesce(nullif(x->>'debit', '')::numeric, 0) > 0) <> (coalesce(nullif(x->>'credit', '')::numeric, 0) > 0))
  ) then
    raise exception 'Each line needs either a debit or a credit amount, not both';
  end if;
  select coalesce(sum(round(coalesce(nullif(x->>'debit', '')::numeric, 0), 2)), 0),
         coalesce(sum(round(coalesce(nullif(x->>'credit', '')::numeric, 0), 2)), 0)
    into v_debit, v_credit
  from jsonb_array_elements(p_lines) x;
  if v_debit <> v_credit then
    raise exception 'Debits (%) and credits (%) must be equal', v_debit, v_credit;
  end if;
  if v_debit <= 0 then raise exception 'The voucher amount must be greater than zero'; end if;
  if exists (
    select 1 from jsonb_array_elements(p_lines) x
    left join accounts a on a.id = nullif(x->>'account_id', '')::uuid and a.org_id = p_org
    where a.id is null or a.is_group or not a.is_active
  ) then
    raise exception 'Every line needs an active, non-group account from this company';
  end if;
  return v_debit;
end $$;

create or replace function public._insert_voucher_lines(p_org uuid, p_voucher uuid, p_lines jsonb)
returns void language sql security definer set search_path = public as $$
  insert into voucher_lines (org_id, voucher_id, line_no, account_id, party_id, description, debit, credit)
  select p_org, p_voucher, t.n::int,
         (t.x->>'account_id')::uuid,
         nullif(t.x->>'party_id', '')::uuid,
         nullif(t.x->>'description', ''),
         round(coalesce(nullif(t.x->>'debit', '')::numeric, 0), 2),
         round(coalesce(nullif(t.x->>'credit', '')::numeric, 0), 2)
  from jsonb_array_elements(p_lines) with ordinality as t(x, n);
$$;

-- Creates a voucher and posts it in one step (used by system-generated entries).
create or replace function public._post_new_voucher(
  p_org uuid, p_type text, p_date date, p_narration text, p_reference text, p_branch uuid,
  p_lines jsonb, p_source_type text default null, p_source_id uuid default null,
  p_reversal_of uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid := gen_random_uuid(); v_uid uuid := auth.uid(); v_total numeric;
begin
  v_total := public._validate_voucher_lines(p_org, p_lines);
  insert into vouchers (id, org_id, voucher_type, voucher_no, voucher_date, status, narration, reference,
                        branch_id, total_amount, source_type, source_id, reversal_of, created_by)
  values (v_id, p_org, p_type, public.next_doc_number(p_org, p_type), p_date, 'draft', p_narration, p_reference,
          p_branch, v_total, p_source_type, p_source_id, p_reversal_of, v_uid);
  perform public._insert_voucher_lines(p_org, v_id, p_lines);
  update vouchers set status = 'posted', approved_by = v_uid, approved_at = now(),
                      posted_by = v_uid, posted_at = now()
  where id = v_id;
  return v_id;
end $$;

-- Reverses a posted voucher by posting an equal and opposite voucher.
create or replace function public._reverse_voucher(p_id uuid, p_date date, p_reason text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v vouchers%rowtype; v_new uuid; v_lines jsonb;
begin
  select * into v from vouchers where id = p_id for update;
  if not found then raise exception 'Voucher not found'; end if;
  if v.status <> 'posted' then raise exception 'Only posted vouchers can be reversed'; end if;
  if v.reversed_by is not null then raise exception 'This voucher has already been reversed'; end if;
  if v.reversal_of is not null then raise exception 'A reversal voucher cannot be reversed again'; end if;

  select jsonb_agg(jsonb_build_object(
           'account_id', l.account_id, 'party_id', l.party_id, 'description', l.description,
           'debit', l.credit, 'credit', l.debit) order by l.line_no)
    into v_lines from voucher_lines l where l.voucher_id = p_id;

  v_new := public._post_new_voucher(
    v.org_id, v.voucher_type, coalesce(p_date, current_date),
    'Reversal of ' || v.voucher_no || coalesce(': ' || nullif(btrim(p_reason), ''), ''),
    v.reference, v.branch_id, v_lines, v.source_type, v.source_id, p_id);
  update vouchers set reversed_by = v_new where id = p_id;
  return v_new;
end $$;

-- ---------------------------------------------------------------------
-- Default chart of accounts for every organization
-- ---------------------------------------------------------------------
create or replace function public._seed_account(
  p_org uuid, p_code text, p_name text, p_type text, p_parent text, p_group boolean, p_key text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_parent uuid; v_id uuid;
begin
  if p_parent is not null then
    select id into v_parent from accounts where org_id = p_org and code = p_parent;
  end if;
  insert into accounts (org_id, code, name, account_type, parent_id, is_group, is_system, system_key)
  values (p_org, p_code, p_name, p_type, v_parent, p_group, true, p_key)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.seed_finance_defaults(p_org uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_cash uuid;
begin
  perform set_config('app.skip_audit', 'on', true);

  perform _seed_account(p_org, '1000', 'Assets', 'asset', null, true);
  perform _seed_account(p_org, '1100', 'Current assets', 'asset', '1000', true);
  perform _seed_account(p_org, '1110', 'Cash in hand', 'asset', '1100', true);
  perform _seed_account(p_org, '1120', 'Bank accounts', 'asset', '1100', true);
  perform _seed_account(p_org, '1130', 'Mobile wallets', 'asset', '1100', true);
  perform _seed_account(p_org, '1200', 'Accounts receivable', 'asset', '1100', false, 'accounts_receivable');
  perform _seed_account(p_org, '1300', 'Inventory', 'asset', '1100', false, 'inventory');
  perform _seed_account(p_org, '1400', 'Advances to suppliers', 'asset', '1100', false, 'supplier_advance');
  perform _seed_account(p_org, '1500', 'Input tax receivable', 'asset', '1100', false, 'input_tax');
  perform _seed_account(p_org, '1600', 'Fixed assets', 'asset', '1000', true);
  perform _seed_account(p_org, '1610', 'Furniture and equipment', 'asset', '1600', false);
  perform _seed_account(p_org, '1620', 'Vehicles', 'asset', '1600', false);
  perform _seed_account(p_org, '1690', 'Accumulated depreciation', 'asset', '1600', false);

  perform _seed_account(p_org, '2000', 'Liabilities', 'liability', null, true);
  perform _seed_account(p_org, '2100', 'Accounts payable', 'liability', '2000', false, 'accounts_payable');
  perform _seed_account(p_org, '2200', 'Customer advances', 'liability', '2000', false, 'customer_advance');
  perform _seed_account(p_org, '2300', 'Output tax payable', 'liability', '2000', false, 'output_tax');
  perform _seed_account(p_org, '2400', 'Accrued expenses', 'liability', '2000', false);
  perform _seed_account(p_org, '2500', 'Loans payable', 'liability', '2000', false);

  perform _seed_account(p_org, '3000', 'Equity', 'equity', null, true);
  perform _seed_account(p_org, '3100', 'Owner capital', 'equity', '3000', false);
  perform _seed_account(p_org, '3200', 'Retained earnings', 'equity', '3000', false, 'retained_earnings');
  perform _seed_account(p_org, '3300', 'Owner drawings', 'equity', '3000', false);
  perform _seed_account(p_org, '3900', 'Opening balance equity', 'equity', '3000', false, 'opening_balance_equity');

  perform _seed_account(p_org, '4000', 'Income', 'income', null, true);
  perform _seed_account(p_org, '4100', 'Sales revenue', 'income', '4000', false, 'sales_revenue');
  perform _seed_account(p_org, '4200', 'Service revenue', 'income', '4000', false);
  perform _seed_account(p_org, '4300', 'Other income', 'income', '4000', false);

  perform _seed_account(p_org, '5000', 'Expenses', 'expense', null, true);
  perform _seed_account(p_org, '5100', 'Cost of goods sold', 'expense', '5000', false, 'cogs');
  perform _seed_account(p_org, '5300', 'Salaries and wages', 'expense', '5000', false);
  perform _seed_account(p_org, '5310', 'Rent', 'expense', '5000', false);
  perform _seed_account(p_org, '5320', 'Utilities', 'expense', '5000', false);
  perform _seed_account(p_org, '5330', 'Transport and delivery', 'expense', '5000', false);
  perform _seed_account(p_org, '5340', 'Office supplies', 'expense', '5000', false);
  perform _seed_account(p_org, '5350', 'Marketing and advertising', 'expense', '5000', false);
  perform _seed_account(p_org, '5360', 'Repairs and maintenance', 'expense', '5000', false);
  perform _seed_account(p_org, '5370', 'Professional fees', 'expense', '5000', false);
  perform _seed_account(p_org, '5380', 'Bank charges', 'expense', '5000', false);
  perform _seed_account(p_org, '5390', 'Telephone and internet', 'expense', '5000', false);
  perform _seed_account(p_org, '5400', 'Depreciation', 'expense', '5000', false);
  perform _seed_account(p_org, '5900', 'Miscellaneous expense', 'expense', '5000', false);

  v_cash := _seed_account(p_org, '1111', 'Cash in hand', 'asset', '1110', false);
  insert into financial_accounts (org_id, kind, name, account_id) values (p_org, 'cash', 'Cash in hand', v_cash);

  perform set_config('app.skip_audit', 'off', true);
end $$;

create or replace function public.trg_seed_org_finance()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.seed_finance_defaults(new.id);
  return new;
end $$;

-- Named so it fires after trg_seed_org_core and before trg_seed_org_masters.
create trigger trg_seed_org_finance after insert on public.organizations
  for each row execute function public.trg_seed_org_finance();

-- ---------------------------------------------------------------------
-- Cash and bank accounts
-- ---------------------------------------------------------------------
create or replace function public.create_financial_account(
  p_org uuid, p_kind text, p_name text, p_bank_name text default null, p_branch_name text default null,
  p_account_number text default null, p_opening_balance numeric default 0, p_opening_date date default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_parent_code text; v_parent uuid; v_code text; v_gl uuid; v_id uuid; v_equity uuid; v_amount numeric;
begin
  if not public.has_permission(p_org, 'finance', 'create') then
    raise exception 'You do not have permission to create cash or bank accounts';
  end if;
  if coalesce(btrim(p_name), '') = '' then raise exception 'Account name is required'; end if;
  v_parent_code := case p_kind when 'cash' then '1110' when 'bank' then '1120' when 'mobile_wallet' then '1130'
                   else null end;
  if v_parent_code is null then raise exception 'Unknown account kind'; end if;

  select id into v_parent from accounts where org_id = p_org and code = v_parent_code;
  select (coalesce(max(case when code ~ '^[0-9]+$' then code::bigint end), v_parent_code::bigint) + 1)::text
    into v_code from accounts where org_id = p_org and parent_id = v_parent;

  insert into accounts (org_id, code, name, account_type, parent_id, is_group)
  values (p_org, v_code, btrim(p_name), 'asset', v_parent, false) returning id into v_gl;

  insert into financial_accounts (org_id, kind, name, account_id, bank_name, branch_name, account_number)
  values (p_org, p_kind, btrim(p_name), v_gl, nullif(btrim(p_bank_name), ''), nullif(btrim(p_branch_name), ''),
          nullif(btrim(p_account_number), ''))
  returning id into v_id;

  v_amount := coalesce(p_opening_balance, 0);
  if v_amount <> 0 then
    select id into v_equity from accounts where org_id = p_org and system_key = 'opening_balance_equity';
    perform public._post_new_voucher(
      p_org, 'journal', coalesce(p_opening_date, current_date), 'Opening balance: ' || btrim(p_name), null, null,
      jsonb_build_array(
        jsonb_build_object('account_id', v_gl, 'debit', greatest(v_amount, 0), 'credit', greatest(-v_amount, 0)),
        jsonb_build_object('account_id', v_equity, 'debit', greatest(-v_amount, 0), 'credit', greatest(v_amount, 0))),
      'financial_account', v_id);
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Voucher workflow
-- ---------------------------------------------------------------------
create or replace function public.save_voucher(
  p_id uuid, p_org uuid, p_type text, p_date date, p_narration text, p_reference text, p_branch uuid, p_lines jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_old vouchers%rowtype; v_id uuid; v_total numeric;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if p_type not in ('journal', 'payment', 'receipt', 'contra', 'debit_note', 'credit_note') then
    raise exception 'Unknown voucher type';
  end if;

  if p_id is not null then select * into v_old from vouchers where id = p_id; end if;

  if v_old.id is not null then
    if v_old.org_id <> p_org then raise exception 'Voucher not found'; end if;
    if not (public.has_permission(p_org, 'finance', 'edit')
            or (v_old.created_by = v_uid and public.has_permission(p_org, 'finance', 'create'))) then
      raise exception 'You do not have permission to edit this voucher';
    end if;
    if v_old.status not in ('draft', 'rejected') then
      raise exception 'Only draft or rejected vouchers can be edited';
    end if;
    if v_old.voucher_type <> p_type then raise exception 'The voucher type cannot be changed'; end if;
  elsif not public.has_permission(p_org, 'finance', 'create') then
    raise exception 'You do not have permission to create vouchers';
  end if;

  v_total := public._validate_voucher_lines(p_org, p_lines);

  if v_old.id is not null then
    v_id := v_old.id;
    update vouchers set voucher_date = coalesce(p_date, current_date), narration = nullif(btrim(p_narration), ''),
           reference = nullif(btrim(p_reference), ''), branch_id = p_branch, total_amount = v_total,
           status = 'draft', rejection_reason = null
    where id = v_id;
    delete from voucher_lines where voucher_id = v_id;
  else
    v_id := coalesce(p_id, gen_random_uuid());
    insert into vouchers (id, org_id, voucher_type, voucher_no, voucher_date, narration, reference, branch_id,
                          total_amount, created_by)
    values (v_id, p_org, p_type, public.next_doc_number(p_org, p_type), coalesce(p_date, current_date),
            nullif(btrim(p_narration), ''), nullif(btrim(p_reference), ''), p_branch, v_total, v_uid);
  end if;

  perform public._insert_voucher_lines(p_org, v_id, p_lines);
  return v_id;
end $$;

create or replace function public.submit_voucher(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v vouchers%rowtype; v_uid uuid := auth.uid();
begin
  select * into v from vouchers where id = p_id for update;
  if not found then raise exception 'Voucher not found'; end if;
  if not (public.has_permission(v.org_id, 'finance', 'edit')
          or (v.created_by = v_uid and public.has_permission(v.org_id, 'finance', 'create'))) then
    raise exception 'You do not have permission to submit this voucher';
  end if;
  if v.status not in ('draft', 'rejected') then raise exception 'Only draft or rejected vouchers can be submitted'; end if;
  update vouchers set status = 'pending', submitted_at = now(), rejection_reason = null where id = p_id;
  perform public.notify_members_with_permission(
    v.org_id, 'finance', 'approve', 'Voucher awaiting approval',
    v.voucher_no || ' for ' || v.total_amount::text, 'approval', 'voucher', p_id);
end $$;

create or replace function public.approve_voucher(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v vouchers%rowtype;
begin
  select * into v from vouchers where id = p_id for update;
  if not found then raise exception 'Voucher not found'; end if;
  if not public.has_permission(v.org_id, 'finance', 'approve') then
    raise exception 'You do not have permission to approve vouchers';
  end if;
  if v.status <> 'pending' then raise exception 'Only pending vouchers can be approved'; end if;
  update vouchers set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_id;
  perform public._notify_user(v.org_id, v.created_by, 'Voucher approved', v.voucher_no, 'approval', 'voucher', p_id);
end $$;

create or replace function public.reject_voucher(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v vouchers%rowtype;
begin
  select * into v from vouchers where id = p_id for update;
  if not found then raise exception 'Voucher not found'; end if;
  if not public.has_permission(v.org_id, 'finance', 'approve') then
    raise exception 'You do not have permission to reject vouchers';
  end if;
  if v.status <> 'pending' then raise exception 'Only pending vouchers can be rejected'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'A reason is required to reject a voucher'; end if;
  update vouchers set status = 'rejected', rejection_reason = btrim(p_reason) where id = p_id;
  perform public._notify_user(v.org_id, v.created_by, 'Voucher rejected', v.voucher_no || ': ' || btrim(p_reason),
                              'warning', 'voucher', p_id);
end $$;

create or replace function public.post_voucher(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v vouchers%rowtype; v_lines jsonb; v_total numeric;
begin
  select * into v from vouchers where id = p_id for update;
  if not found then raise exception 'Voucher not found'; end if;
  if not public.has_permission(v.org_id, 'finance', 'approve') then
    raise exception 'You do not have permission to post vouchers';
  end if;
  if v.status not in ('draft', 'pending', 'approved') then
    raise exception 'This voucher cannot be posted from status %', v.status;
  end if;

  select jsonb_agg(jsonb_build_object('account_id', account_id, 'debit', debit, 'credit', credit))
    into v_lines from voucher_lines where voucher_id = p_id;
  v_total := public._validate_voucher_lines(v.org_id, v_lines);

  update vouchers set status = 'posted', total_amount = v_total,
         approved_by = coalesce(approved_by, auth.uid()), approved_at = coalesce(approved_at, now()),
         posted_by = auth.uid(), posted_at = now()
  where id = p_id;
  perform public._notify_user(v.org_id, v.created_by, 'Voucher posted', v.voucher_no, 'info', 'voucher', p_id);
end $$;

create or replace function public.reverse_voucher(p_id uuid, p_date date default null, p_reason text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_org uuid;
begin
  select org_id into v_org from vouchers where id = p_id;
  if v_org is null then raise exception 'Voucher not found'; end if;
  if not public.has_permission(v_org, 'finance', 'approve') then
    raise exception 'You do not have permission to reverse vouchers';
  end if;
  return public._reverse_voucher(p_id, p_date, p_reason);
end $$;

create or replace function public.discard_voucher(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v vouchers%rowtype;
begin
  select * into v from vouchers where id = p_id for update;
  if not found then raise exception 'Voucher not found'; end if;
  if not (public.has_permission(v.org_id, 'finance', 'delete')
          or (v.created_by = auth.uid() and public.has_permission(v.org_id, 'finance', 'create'))) then
    raise exception 'You do not have permission to delete this voucher';
  end if;
  if v.status not in ('draft', 'rejected') then
    raise exception 'Only draft or rejected vouchers can be deleted. Reverse posted vouchers instead.';
  end if;
  delete from attachments where org_id = v.org_id and entity_type = 'voucher' and entity_id = p_id;
  delete from vouchers where id = p_id;
end $$;

-- ---------------------------------------------------------------------
-- Income and expense workflow
-- ---------------------------------------------------------------------
create or replace function public._pay_transaction(p_id uuid, p_fin uuid, p_date date)
returns void language plpgsql security definer set search_path = public as $$
declare t income_expenses%rowtype; f financial_accounts%rowtype; v_voucher uuid; v_lines jsonb;
begin
  select * into t from income_expenses where id = p_id for update;
  select * into f from financial_accounts where id = p_fin and org_id = t.org_id and is_active;
  if not found then raise exception 'Choose an active cash or bank account'; end if;

  if t.kind = 'expense' then
    v_lines := jsonb_build_array(
      jsonb_build_object('account_id', t.account_id, 'party_id', t.party_id, 'description', t.description, 'debit', t.amount),
      jsonb_build_object('account_id', f.account_id, 'description', t.description, 'credit', t.amount));
  else
    v_lines := jsonb_build_array(
      jsonb_build_object('account_id', f.account_id, 'description', t.description, 'debit', t.amount),
      jsonb_build_object('account_id', t.account_id, 'party_id', t.party_id, 'description', t.description, 'credit', t.amount));
  end if;

  v_voucher := public._post_new_voucher(
    t.org_id, case when t.kind = 'expense' then 'payment' else 'receipt' end, coalesce(p_date, t.txn_date),
    coalesce(t.description, t.number), t.reference, t.branch_id, v_lines, t.kind, t.id);

  update income_expenses set status = case when kind = 'expense' then 'paid' else 'received' end,
         financial_account_id = p_fin, voucher_id = v_voucher where id = p_id;
end $$;

create or replace function public.save_expense(
  p_id uuid, p_org uuid, p_date date, p_account uuid, p_amount numeric, p_payee text, p_party uuid,
  p_description text, p_reference text, p_branch uuid, p_department uuid,
  p_submit boolean default true, p_pay_from uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_old income_expenses%rowtype; v_id uuid; v_status text; v_number text;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if p_id is not null then select * into v_old from income_expenses where id = p_id; end if;

  if v_old.id is not null then
    if v_old.org_id <> p_org or v_old.kind <> 'expense' then raise exception 'Expense not found'; end if;
    if v_old.requested_by <> v_uid or v_old.status not in ('draft', 'rejected') then
      raise exception 'Only your own draft or rejected requests can be edited';
    end if;
  elsif not public.has_permission(p_org, 'expenses', 'create') then
    raise exception 'You do not have permission to create expenses';
  end if;

  if coalesce(p_amount, 0) <= 0 then raise exception 'Enter an amount greater than zero'; end if;
  if not exists (select 1 from accounts where id = p_account and org_id = p_org and account_type = 'expense'
                 and not is_group and is_active) then
    raise exception 'Choose an active expense head';
  end if;

  if p_pay_from is not null and not (public.has_permission(p_org, 'expenses', 'approve')
                                     and public.has_permission(p_org, 'finance', 'create')) then
    raise exception 'You do not have permission to pay an expense directly';
  end if;

  v_status := case when p_submit then 'pending' else 'draft' end;

  if v_old.id is not null then
    v_id := v_old.id;
    update income_expenses set txn_date = coalesce(p_date, current_date), account_id = p_account, amount = p_amount,
           payee = nullif(btrim(p_payee), ''), party_id = p_party, description = nullif(btrim(p_description), ''),
           reference = nullif(btrim(p_reference), ''), branch_id = p_branch, department_id = p_department,
           status = v_status, rejection_reason = null
    where id = v_id;
  else
    v_id := coalesce(p_id, gen_random_uuid());
    v_number := public.next_doc_number(p_org, 'expense');
    insert into income_expenses (id, org_id, kind, number, txn_date, account_id, amount, payee, party_id, description,
                                 reference, branch_id, department_id, status, requested_by)
    values (v_id, p_org, 'expense', v_number, coalesce(p_date, current_date), p_account, p_amount,
            nullif(btrim(p_payee), ''), p_party, nullif(btrim(p_description), ''), nullif(btrim(p_reference), ''),
            p_branch, p_department, v_status, v_uid);
  end if;

  if p_pay_from is not null and p_submit then
    update income_expenses set status = 'approved', approved_by = v_uid, approved_at = now() where id = v_id;
    perform public._pay_transaction(v_id, p_pay_from, p_date);
  elsif p_submit then
    select number into v_number from income_expenses where id = v_id;
    perform public.notify_members_with_permission(
      p_org, 'expenses', 'approve', 'Expense awaiting approval', v_number || ' for ' || p_amount::text,
      'approval', 'expense', v_id);
  end if;
  return v_id;
end $$;

create or replace function public.approve_expense(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare t income_expenses%rowtype;
begin
  select * into t from income_expenses where id = p_id for update;
  if not found or t.kind <> 'expense' then raise exception 'Expense not found'; end if;
  if not public.has_permission(t.org_id, 'expenses', 'approve') then
    raise exception 'You do not have permission to approve expenses';
  end if;
  if t.status <> 'pending' then raise exception 'Only pending expenses can be approved'; end if;
  update income_expenses set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_id;
  perform public._notify_user(t.org_id, t.requested_by, 'Expense approved', t.number, 'approval', 'expense', p_id);
  perform public.notify_members_with_permission(
    t.org_id, 'finance', 'create', 'Approved expense ready for payment', t.number || ' for ' || t.amount::text,
    'info', 'expense', p_id);
end $$;

create or replace function public.reject_expense(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare t income_expenses%rowtype;
begin
  select * into t from income_expenses where id = p_id for update;
  if not found or t.kind <> 'expense' then raise exception 'Expense not found'; end if;
  if not public.has_permission(t.org_id, 'expenses', 'approve') then
    raise exception 'You do not have permission to reject expenses';
  end if;
  if t.status <> 'pending' then raise exception 'Only pending expenses can be rejected'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'A reason is required to reject an expense'; end if;
  update income_expenses set status = 'rejected', rejection_reason = btrim(p_reason) where id = p_id;
  perform public._notify_user(t.org_id, t.requested_by, 'Expense rejected', t.number || ': ' || btrim(p_reason),
                              'warning', 'expense', p_id);
end $$;

create or replace function public.pay_expense(p_id uuid, p_fin uuid, p_date date default null)
returns void language plpgsql security definer set search_path = public as $$
declare t income_expenses%rowtype;
begin
  select * into t from income_expenses where id = p_id for update;
  if not found or t.kind <> 'expense' then raise exception 'Expense not found'; end if;
  if not public.has_permission(t.org_id, 'finance', 'create') then
    raise exception 'You do not have permission to record payments';
  end if;
  if t.status <> 'approved' then raise exception 'Only approved expenses can be paid'; end if;
  perform public._pay_transaction(p_id, p_fin, p_date);
  perform public._notify_user(t.org_id, t.requested_by, 'Expense paid', t.number, 'info', 'expense', p_id);
end $$;

create or replace function public.record_income(
  p_id uuid, p_org uuid, p_date date, p_account uuid, p_amount numeric, p_fin uuid, p_payer text,
  p_party uuid, p_description text, p_reference text, p_branch uuid
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.has_permission(p_org, 'finance', 'create') then
    raise exception 'You do not have permission to record income';
  end if;
  if coalesce(p_amount, 0) <= 0 then raise exception 'Enter an amount greater than zero'; end if;
  if not exists (select 1 from accounts where id = p_account and org_id = p_org and account_type = 'income'
                 and not is_group and is_active) then
    raise exception 'Choose an active income head';
  end if;
  v_id := coalesce(p_id, gen_random_uuid());
  insert into income_expenses (id, org_id, kind, number, txn_date, account_id, amount, payee, party_id, description,
                               reference, branch_id, status, requested_by, approved_by, approved_at)
  values (v_id, p_org, 'income', public.next_doc_number(p_org, 'income'), coalesce(p_date, current_date), p_account,
          p_amount, nullif(btrim(p_payer), ''), p_party, nullif(btrim(p_description), ''),
          nullif(btrim(p_reference), ''), p_branch, 'approved', auth.uid(), auth.uid(), now());
  perform public._pay_transaction(v_id, p_fin, p_date);
  return v_id;
end $$;

-- Cancels a request, or reverses the voucher of a paid or received entry.
create or replace function public.cancel_transaction(p_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare t income_expenses%rowtype;
begin
  select * into t from income_expenses where id = p_id for update;
  if not found then raise exception 'Entry not found'; end if;
  if t.status in ('paid', 'received') then
    if not public.has_permission(t.org_id, 'finance', 'approve') then
      raise exception 'You do not have permission to cancel a posted entry';
    end if;
    perform public._reverse_voucher(t.voucher_id, current_date, coalesce(p_reason, 'Cancelled ' || t.number));
  elsif t.status in ('draft', 'pending', 'rejected', 'approved') then
    if not (t.requested_by = auth.uid() or public.has_permission(t.org_id, 'expenses', 'approve')) then
      raise exception 'You do not have permission to cancel this entry';
    end if;
  else
    raise exception 'This entry is already cancelled';
  end if;
  update income_expenses set status = 'cancelled', rejection_reason = nullif(btrim(p_reason), '') where id = p_id;
end $$;

-- ---------------------------------------------------------------------
-- Balances and ledgers (read-only, governed by row level security)
-- ---------------------------------------------------------------------
create or replace function public.account_balances(p_org uuid, p_to date default null)
returns table (account_id uuid, total_debit numeric, total_credit numeric)
language sql stable as $$
  select l.account_id, sum(l.debit), sum(l.credit)
  from voucher_lines l
  join vouchers v on v.id = l.voucher_id
  where l.org_id = p_org and v.status = 'posted' and (p_to is null or v.voucher_date <= p_to)
  group by l.account_id;
$$;

create or replace function public.account_ledger(p_org uuid, p_account uuid, p_from date, p_to date)
returns table (
  row_type text, entry_date date, voucher_id uuid, voucher_no text, voucher_type text, narration text,
  party_name text, debit numeric, credit numeric, balance numeric
) language sql stable as $$
  with sgn as (
    select case when account_type in ('asset', 'expense') then 1 else -1 end as s
    from accounts where id = p_account and org_id = p_org
  ),
  opening as (
    select coalesce(sum(l.debit - l.credit), 0) * coalesce((select s from sgn), 1) as bal
    from voucher_lines l join vouchers v on v.id = l.voucher_id
    where l.org_id = p_org and l.account_id = p_account and v.status = 'posted' and v.voucher_date < p_from
  ),
  entries as (
    select v.voucher_date, v.created_at, l.line_no, v.id as vid, v.voucher_no, v.voucher_type,
           coalesce(l.description, v.narration) as narration, p.name as party_name, l.debit, l.credit
    from voucher_lines l
    join vouchers v on v.id = l.voucher_id
    left join parties p on p.id = l.party_id
    where l.org_id = p_org and l.account_id = p_account and v.status = 'posted'
      and v.voucher_date between p_from and p_to
  ),
  running as (
    select e.*,
           row_number() over w as seq,
           (select bal from opening)
             + sum((e.debit - e.credit) * coalesce((select s from sgn), 1)) over w as bal
    from entries e
    window w as (order by e.voucher_date, e.created_at, e.voucher_no, e.line_no
                 rows between unbounded preceding and current row)
  )
  select u.row_type, u.entry_date, u.vid, u.voucher_no, u.voucher_type, u.narration, u.party_name,
         u.debit, u.credit, u.balance
  from (
    select 'opening'::text as row_type, p_from as entry_date, null::uuid as vid, null::text as voucher_no,
           null::text as voucher_type, 'Opening balance'::text as narration, null::text as party_name,
           null::numeric as debit, null::numeric as credit, (select bal from opening) as balance, 0::bigint as seq
    union all
    select 'entry', voucher_date, vid, voucher_no, voucher_type, narration, party_name, debit, credit, bal, seq
    from running
  ) u
  order by u.seq;
$$;

-- ---------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------
alter table public.accounts enable row level security;
create policy accounts_select on public.accounts for select to authenticated
  using (public.has_permission(org_id, 'finance', 'view') or public.has_permission(org_id, 'expenses', 'view'));
create policy accounts_insert on public.accounts for insert to authenticated
  with check (public.has_permission(org_id, 'finance', 'create') and not is_system and system_key is null);
create policy accounts_update on public.accounts for update to authenticated
  using (public.has_permission(org_id, 'finance', 'edit'))
  with check (public.has_permission(org_id, 'finance', 'edit'));
create policy accounts_delete on public.accounts for delete to authenticated
  using (public.has_permission(org_id, 'finance', 'delete') and not is_system);

alter table public.vouchers enable row level security;
create policy vouchers_select on public.vouchers for select to authenticated
  using (public.has_permission(org_id, 'finance', 'view'));

alter table public.voucher_lines enable row level security;
create policy voucher_lines_select on public.voucher_lines for select to authenticated
  using (public.has_permission(org_id, 'finance', 'view'));

alter table public.financial_accounts enable row level security;
create policy financial_accounts_select on public.financial_accounts for select to authenticated
  using (public.has_permission(org_id, 'finance', 'view') or public.has_permission(org_id, 'expenses', 'approve'));
create policy financial_accounts_update on public.financial_accounts for update to authenticated
  using (public.has_permission(org_id, 'finance', 'edit'))
  with check (public.has_permission(org_id, 'finance', 'edit'));

alter table public.income_expenses enable row level security;
create policy income_expenses_select on public.income_expenses for select to authenticated
  using (
    public.has_permission(org_id, 'expenses', 'view')
    and (kind = 'expense' or public.has_permission(org_id, 'finance', 'view'))
    and (requested_by = auth.uid()
         or public.has_permission(org_id, 'expenses', 'approve')
         or public.has_permission(org_id, 'finance', 'view'))
  );

-- Attachments follow the permission of the record they belong to.
create or replace function public.can_view_attachment(p_org uuid, p_entity_type text)
returns boolean language sql stable security definer set search_path = public as $$
  select case p_entity_type
    when 'voucher' then public.has_permission(p_org, 'finance', 'view')
    when 'expense' then public.has_permission(p_org, 'expenses', 'view')
    when 'income' then public.has_permission(p_org, 'finance', 'view')
    else public.is_org_member(p_org)
  end;
$$;
drop policy if exists att_select on public.attachments;
create policy att_select on public.attachments for select to authenticated
  using (public.can_view_attachment(org_id, entity_type));

select public.enable_audit('public.accounts');
select public.enable_audit('public.financial_accounts');
select public.enable_audit('public.vouchers');
select public.enable_audit('public.income_expenses');

-- ---------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
           where p.pronamespace = 'public'::regnamespace
             and p.proname in ('create_financial_account', 'save_voucher', 'submit_voucher', 'approve_voucher',
                               'reject_voucher', 'post_voucher', 'reverse_voucher', 'discard_voucher',
                               'save_expense', 'approve_expense', 'reject_expense', 'pay_expense',
                               'record_income', 'cancel_transaction', 'account_balances', 'account_ledger')
  loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;

  for f in select p.oid::regprocedure from pg_proc p
           where p.pronamespace = 'public'::regnamespace
             and p.proname in ('_notify_user', '_validate_voucher_lines', '_insert_voucher_lines',
                               '_post_new_voucher', '_reverse_voucher', '_seed_account', '_pay_transaction',
                               'seed_finance_defaults')
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
  for o in select id from organizations where not exists (select 1 from accounts a where a.org_id = organizations.id)
  loop
    perform public.seed_finance_defaults(o.id);
  end loop;
end $$;
