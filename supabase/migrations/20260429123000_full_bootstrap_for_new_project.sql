-- Combined bootstrap SQL for new Supabase project
-- Generated automatically from ordered migrations

-- >>> BEGIN 20260316101822_a92da35c-554c-4a86-8a48-8d93cb25eccb.sql

-- Create app_role enum
create type public.app_role as enum ('super_admin', 'company_admin', 'staff');

-- Organizations
create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz default now()
);

-- Company requests
create table public.company_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  company_name text not null,
  admin_name text not null,
  email text not null,
  status text not null default 'pending',
  created_at timestamptz default now()
);

-- Services
create table public.services (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade not null,
  name text not null,
  prefix char(1) not null default 'A',
  created_at timestamptz default now()
);

-- Counters
create table public.counters (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade not null,
  service_id uuid references public.services(id) on delete cascade,
  counter_number int not null,
  created_at timestamptz default now()
);

-- Tokens
create table public.tokens (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade not null,
  service_id uuid references public.services(id) on delete cascade not null,
  token_number text not null,
  status text not null default 'waiting',
  counter_id uuid references public.counters(id) on delete set null,
  created_at timestamptz default now()
);

-- Staff requests
create table public.staff_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  organization_id uuid references public.organizations(id) on delete cascade not null,
  name text not null,
  email text not null,
  status text not null default 'pending',
  created_at timestamptz default now()
);

-- User roles (separate table as required)
create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  role app_role not null,
  organization_id uuid references public.organizations(id) on delete cascade,
  unique (user_id, role)
);

-- Profiles
create table public.profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null unique,
  name text not null,
  email text not null,
  organization_id uuid references public.organizations(id) on delete cascade,
  created_at timestamptz default now()
);

-- Enable RLS on all tables
alter table public.organizations enable row level security;
alter table public.company_requests enable row level security;
alter table public.services enable row level security;
alter table public.counters enable row level security;
alter table public.tokens enable row level security;
alter table public.staff_requests enable row level security;
alter table public.user_roles enable row level security;
alter table public.profiles enable row level security;

-- Security definer function: check role
create or replace function public.has_role(_user_id uuid, _role app_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = _user_id and role = _role
  )
$$;

-- Security definer function: get user org
create or replace function public.get_user_org(_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select organization_id from public.user_roles
  where user_id = _user_id limit 1
$$;

-- Generate token function
create or replace function public.generate_token(_service_id uuid, _org_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  _prefix char;
  _count int;
  _token text;
begin
  select upper(left(name, 1)) into _prefix from public.services where id = _service_id;
  select count(*) + 1 into _count from public.tokens
    where service_id = _service_id and created_at::date = current_date;
  _token := _prefix || lpad(_count::text, 3, '0');
  insert into public.tokens (organization_id, service_id, token_number, status)
    values (_org_id, _service_id, _token, 'waiting');
  return _token;
end;
$$;

-- RLS Policies

-- company_requests
create policy "Anyone can submit company request" on public.company_requests for insert to anon, authenticated with check (true);
create policy "Super admins can view requests" on public.company_requests for select to authenticated using (public.has_role(auth.uid(), 'super_admin'));
create policy "Super admins can update requests" on public.company_requests for update to authenticated using (public.has_role(auth.uid(), 'super_admin'));

-- organizations
create policy "Members can view own org" on public.organizations for select to authenticated using (
  id = public.get_user_org(auth.uid()) or public.has_role(auth.uid(), 'super_admin')
);
create policy "Super admins can insert orgs" on public.organizations for insert to authenticated with check (public.has_role(auth.uid(), 'super_admin'));

-- user_roles
create policy "Users can view own role" on public.user_roles for select to authenticated using (
  user_id = auth.uid() or public.has_role(auth.uid(), 'super_admin')
);
create policy "Admins can insert roles" on public.user_roles for insert to authenticated with check (
  public.has_role(auth.uid(), 'super_admin') or
  (public.has_role(auth.uid(), 'company_admin') and organization_id = public.get_user_org(auth.uid()))
);

-- profiles
create policy "Users can view relevant profiles" on public.profiles for select to authenticated using (
  user_id = auth.uid() or public.has_role(auth.uid(), 'super_admin') or organization_id = public.get_user_org(auth.uid())
);
create policy "Admins can insert profiles" on public.profiles for insert to authenticated with check (
  user_id = auth.uid() or public.has_role(auth.uid(), 'super_admin') or
  (public.has_role(auth.uid(), 'company_admin') and organization_id = public.get_user_org(auth.uid()))
);
create policy "Users can update own profile" on public.profiles for update to authenticated using (user_id = auth.uid());

-- services (readable by anyone for kiosk, manageable by company admin)
create policy "Anyone can view services" on public.services for select to anon, authenticated using (true);
create policy "Company admins can insert services" on public.services for insert to authenticated with check (
  organization_id = public.get_user_org(auth.uid()) and public.has_role(auth.uid(), 'company_admin')
);
create policy "Company admins can update services" on public.services for update to authenticated using (
  organization_id = public.get_user_org(auth.uid()) and public.has_role(auth.uid(), 'company_admin')
);
create policy "Company admins can delete services" on public.services for delete to authenticated using (
  organization_id = public.get_user_org(auth.uid()) and public.has_role(auth.uid(), 'company_admin')
);

-- counters
create policy "Anyone can view counters" on public.counters for select to anon, authenticated using (true);
create policy "Company admins can insert counters" on public.counters for insert to authenticated with check (
  organization_id = public.get_user_org(auth.uid()) and public.has_role(auth.uid(), 'company_admin')
);
create policy "Company admins can update counters" on public.counters for update to authenticated using (
  organization_id = public.get_user_org(auth.uid()) and public.has_role(auth.uid(), 'company_admin')
);
create policy "Company admins can delete counters" on public.counters for delete to authenticated using (
  organization_id = public.get_user_org(auth.uid()) and public.has_role(auth.uid(), 'company_admin')
);

-- tokens (public for kiosk/display)
create policy "Anyone can view tokens" on public.tokens for select to anon, authenticated using (true);
create policy "Anyone can insert tokens" on public.tokens for insert to anon, authenticated with check (true);
create policy "Staff can update tokens" on public.tokens for update to authenticated using (
  organization_id = public.get_user_org(auth.uid())
);

-- staff_requests
create policy "Anyone can submit staff request" on public.staff_requests for insert to anon, authenticated with check (true);
create policy "Company admins can view staff requests" on public.staff_requests for select to authenticated using (
  organization_id = public.get_user_org(auth.uid()) and public.has_role(auth.uid(), 'company_admin')
);
create policy "Company admins can update staff requests" on public.staff_requests for update to authenticated using (
  organization_id = public.get_user_org(auth.uid()) and public.has_role(auth.uid(), 'company_admin')
);

-- Enable realtime for tokens
alter publication supabase_realtime add table tokens;

-- <<< END 20260316101822_a92da35c-554c-4a86-8a48-8d93cb25eccb.sql

-- >>> BEGIN 20260316103825_0b669ab8-8edc-4ea3-a891-1908c1beb5d1.sql

DROP POLICY "Admins can insert roles" ON public.user_roles;

CREATE POLICY "Admins can insert roles" ON public.user_roles
  FOR INSERT TO authenticated
  WITH CHECK (
    has_role(auth.uid(), 'super_admin'::app_role)
    OR (
      has_role(auth.uid(), 'company_admin'::app_role)
      AND organization_id = get_user_org(auth.uid())
      AND role <> 'super_admin'::app_role
    )
  );

-- <<< END 20260316103825_0b669ab8-8edc-4ea3-a891-1908c1beb5d1.sql

-- >>> BEGIN 20260316120000_kiosk_priority_print.sql
-- Add queue priority metadata to tokens
alter table public.tokens
add column if not exists priority_level text not null default 'normal',
add column if not exists priority_rank int not null default 4;

-- Ensure only supported priority values are stored
alter table public.tokens
drop constraint if exists tokens_priority_level_check;

alter table public.tokens
add constraint tokens_priority_level_check check (
    priority_level in (
        'normal',
        'vip',
        'elderly',
        'urgent'
    )
);

-- Ensure ranks map to the expected levels
alter table public.tokens
drop constraint if exists tokens_priority_rank_check;

alter table public.tokens
add constraint tokens_priority_rank_check check (priority_rank between 1 and 4);

-- Generate token with explicit priority and configured service prefix
create or replace function public.generate_token_with_priority(
  _service_id uuid,
  _org_id uuid,
  _priority_level text default 'normal'
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  _prefix char;
  _count int;
  _token text;
  _normalized_priority text;
  _priority_rank int;
begin
  _normalized_priority := lower(coalesce(_priority_level, 'normal'));

  if _normalized_priority not in ('normal', 'vip', 'elderly', 'urgent') then
    _normalized_priority := 'normal';
  end if;

  _priority_rank := case _normalized_priority
    when 'urgent' then 1
    when 'vip' then 2
    when 'elderly' then 3
    else 4
  end;

  select coalesce(prefix, upper(left(name, 1)))
    into _prefix
    from public.services
    where id = _service_id;

  if _prefix is null then
    raise exception 'Service not found';
  end if;

  select count(*) + 1 into _count
    from public.tokens
    where service_id = _service_id
      and created_at::date = current_date;

  _token := upper(_prefix) || lpad(_count::text, 3, '0');

  insert into public.tokens (organization_id, service_id, token_number, status, priority_level, priority_rank)
  values (_org_id, _service_id, _token, 'waiting', _normalized_priority, _priority_rank);

  return _token;
end;
$$;

-- Keep backward compatibility while fixing prefix behavior
create or replace function public.generate_token(_service_id uuid, _org_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.generate_token_with_priority(_service_id, _org_id, 'normal');
end;
$$;
-- <<< END 20260316120000_kiosk_priority_print.sql

-- >>> BEGIN 20260323100000_customer_details_queue.sql
-- Add optional customer details to queue tokens
alter table public.tokens
add column if not exists customer_name text,
add column if not exists customer_phone text,
add column if not exists visit_reason text,
add column if not exists notification_channel text,
add column if not exists notification_opt_in boolean default false;

alter table public.tokens
drop constraint if exists tokens_notification_channel_check;

alter table public.tokens
add constraint tokens_notification_channel_check check (
  notification_channel is null or notification_channel in ('none', 'sms', 'whatsapp')
);

-- <<< END 20260323100000_customer_details_queue.sql

-- >>> BEGIN 20260330103000_paystack_billing.sql
-- Track billing and Paystack payment lifecycle for company onboarding
alter table public.company_requests
add column if not exists selected_plan text not null default 'professional',
add column if not exists paystack_reference text,
add column if not exists payment_status text not null default 'unpaid',
add column if not exists payment_amount integer not null default 0,
add column if not exists payment_currency text not null default 'NGN',
add column if not exists paid_at timestamptz,
add column if not exists payment_metadata jsonb not null default '{}'::jsonb;

alter table public.company_requests
drop constraint if exists company_requests_selected_plan_check;

alter table public.company_requests
add constraint company_requests_selected_plan_check check (
  selected_plan in ('starter', 'professional', 'enterprise')
);

alter table public.company_requests
drop constraint if exists company_requests_payment_status_check;

alter table public.company_requests
add constraint company_requests_payment_status_check check (
  payment_status in ('unpaid', 'initialized', 'paid', 'failed', 'abandoned')
);

create unique index if not exists company_requests_paystack_reference_key
  on public.company_requests(paystack_reference)
  where paystack_reference is not null;

create table if not exists public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  request_id uuid references public.company_requests(id) on delete cascade,
  paystack_reference text not null unique,
  plan_id text not null,
  amount integer not null,
  currency text not null,
  status text not null,
  gateway_message text,
  paid_at timestamptz,
  raw_response jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payment_transactions_plan_id_check check (
    plan_id in ('starter', 'professional', 'enterprise')
  )
);

create table if not exists public.organization_subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null unique references public.organizations(id) on delete cascade,
  request_id uuid references public.company_requests(id) on delete set null,
  plan_id text not null,
  status text not null default 'active',
  amount integer not null,
  currency text not null,
  current_period_start timestamptz not null default now(),
  current_period_end timestamptz,
  next_billing_at timestamptz,
  paystack_reference text,
  paystack_customer_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_subscriptions_plan_id_check check (
    plan_id in ('starter', 'professional', 'enterprise')
  ),
  constraint organization_subscriptions_status_check check (
    status in ('active', 'past_due', 'canceled', 'trialing')
  )
);

alter table public.payment_transactions enable row level security;
alter table public.organization_subscriptions enable row level security;

create policy "Company request owner can view payments" on public.payment_transactions
for select to authenticated
using (
  exists (
    select 1
    from public.company_requests cr
    where cr.id = request_id
      and cr.user_id = auth.uid()
  )
  or public.has_role(auth.uid(), 'super_admin')
);

create policy "Admins can view org subscriptions" on public.organization_subscriptions
for select to authenticated
using (
  public.has_role(auth.uid(), 'super_admin')
  or organization_id = public.get_user_org(auth.uid())
);

create policy "Super admins can manage org subscriptions" on public.organization_subscriptions
for all to authenticated
using (public.has_role(auth.uid(), 'super_admin'))
with check (public.has_role(auth.uid(), 'super_admin'));

-- <<< END 20260330103000_paystack_billing.sql

-- >>> BEGIN 20260330121500_dynamic_pricing_multigateway.sql
-- Dynamic pricing, multi-gateway support, and commission tracking

create table if not exists public.billing_plans (
  id text primary key,
  name text not null,
  description text not null,
  amount integer not null,
  currency text not null default 'NGN',
  period_label text not null default '/month',
  features jsonb not null default '[]'::jsonb,
  cta text not null default 'Choose Plan',
  highlighted boolean not null default false,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint billing_plans_amount_check check (amount >= 0)
);

insert into public.billing_plans (
  id, name, description, amount, currency, period_label, features, cta, highlighted, is_active, sort_order
)
values
  (
    'starter',
    'Starter',
    'Perfect for small businesses with a single location.',
    5000,
    'USD',
    '/month',
    '["1 service counter","Up to 3 services","Basic queue display","Token generation","Email support"]'::jsonb,
    'Choose Starter',
    false,
    true,
    1
  ),
  (
    'professional',
    'Professional',
    'For growing businesses needing advanced queue management.',
    10000,
    'USD',
    '/month',
    '["Unlimited counters","Unlimited services","Priority queuing (VIP/Urgent)","Audio announcements","Analytics & reports","Thermal ticket printing","Staff management","Priority support"]'::jsonb,
    'Choose Professional',
    true,
    true,
    2
  ),
  (
    'enterprise',
    'Enterprise',
    'Multi-branch operations with full feature access.',
    15000,
    'USD',
    '/month',
    '["Everything in Professional","Multi-branch support","Advanced queue alerts","Custom branding","API access","Dedicated account manager","SLA guarantee"]'::jsonb,
    'Choose Enterprise',
    false,
    true,
    3
  )
on conflict (id) do update
set
  name = excluded.name,
  description = excluded.description,
  amount = excluded.amount,
  currency = excluded.currency,
  period_label = excluded.period_label,
  features = excluded.features,
  cta = excluded.cta,
  highlighted = excluded.highlighted,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order,
  updated_at = now();

create table if not exists public.platform_payment_settings (
  id integer primary key default 1,
  default_provider text not null default 'paystack',
  commission_type text not null default 'percentage',
  commission_value numeric(8,4) not null default 2.5000,
  commission_flat_amount integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_payment_settings_singleton check (id = 1),
  constraint platform_payment_settings_provider_check check (default_provider in ('paystack', 'flutterwave')),
  constraint platform_payment_settings_commission_type_check check (commission_type in ('percentage', 'flat')),
  constraint platform_payment_settings_commission_value_check check (commission_value >= 0),
  constraint platform_payment_settings_commission_flat_amount_check check (commission_flat_amount >= 0)
);

insert into public.platform_payment_settings (id)
values (1)
on conflict (id) do nothing;

alter table public.company_requests
add column if not exists payment_provider text not null default 'paystack',
add column if not exists payment_reference text;

alter table public.company_requests
drop constraint if exists company_requests_payment_provider_check;

alter table public.company_requests
add constraint company_requests_payment_provider_check check (
  payment_provider in ('paystack', 'flutterwave')
);

create unique index if not exists company_requests_payment_reference_key
  on public.company_requests(payment_reference)
  where payment_reference is not null;

alter table public.payment_transactions
add column if not exists provider text not null default 'paystack',
add column if not exists payment_reference text,
add column if not exists gross_amount integer not null default 0,
add column if not exists commission_amount integer not null default 0,
add column if not exists net_amount integer not null default 0,
add column if not exists gateway_fee integer not null default 0;

update public.payment_transactions
set
  payment_reference = coalesce(payment_reference, paystack_reference),
  gross_amount = case when gross_amount = 0 then amount else gross_amount end,
  net_amount = case when net_amount = 0 then amount else net_amount end
where true;

alter table public.payment_transactions
drop constraint if exists payment_transactions_provider_check;

alter table public.payment_transactions
add constraint payment_transactions_provider_check check (
  provider in ('paystack', 'flutterwave')
);

create unique index if not exists payment_transactions_payment_reference_key
  on public.payment_transactions(payment_reference)
  where payment_reference is not null;

alter table public.organization_subscriptions
add column if not exists payment_provider text not null default 'paystack',
add column if not exists payment_reference text;

alter table public.organization_subscriptions
drop constraint if exists organization_subscriptions_payment_provider_check;

alter table public.organization_subscriptions
add constraint organization_subscriptions_payment_provider_check check (
  payment_provider in ('paystack', 'flutterwave')
);

alter table public.billing_plans enable row level security;
alter table public.platform_payment_settings enable row level security;

create policy "Anyone can view active billing plans" on public.billing_plans
for select to anon, authenticated
using (is_active = true or public.has_role(auth.uid(), 'super_admin'));

create policy "Super admins can manage billing plans" on public.billing_plans
for all to authenticated
using (public.has_role(auth.uid(), 'super_admin'))
with check (public.has_role(auth.uid(), 'super_admin'));

create policy "Authenticated can view payment settings" on public.platform_payment_settings
for select to authenticated
using (true);

create policy "Super admins can manage payment settings" on public.platform_payment_settings
for all to authenticated
using (public.has_role(auth.uid(), 'super_admin'))
with check (public.has_role(auth.uid(), 'super_admin'));

-- <<< END 20260330121500_dynamic_pricing_multigateway.sql

-- >>> BEGIN 20260330133000_multicurrency_plan_prices.sql
-- Multi-currency pricing controlled in Supabase by super admins

-- Ensure base billing_plans table exists when this migration is executed standalone
create table if not exists public.billing_plans (
  id text primary key,
  name text not null,
  description text not null,
  amount integer not null,
  currency text not null default 'USD',
  period_label text not null default '/month',
  features jsonb not null default '[]'::jsonb,
  cta text not null default 'Choose Plan',
  highlighted boolean not null default false,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint billing_plans_amount_check check (amount >= 0)
);

insert into public.billing_plans (
  id, name, description, amount, currency, period_label, features, cta, highlighted, is_active, sort_order
)
values
  (
    'starter',
    'Starter',
    'Perfect for small businesses with a single location.',
    5000,
    'USD',
    '/month',
    '["1 service counter","Up to 3 services","Basic queue display","Token generation","Email support"]'::jsonb,
    'Choose Starter',
    false,
    true,
    1
  ),
  (
    'professional',
    'Professional',
    'For growing businesses needing advanced queue management.',
    10000,
    'USD',
    '/month',
    '["Unlimited counters","Unlimited services","Priority queuing (VIP/Urgent)","Audio announcements","Analytics & reports","Thermal ticket printing","Staff management","Priority support"]'::jsonb,
    'Choose Professional',
    true,
    true,
    2
  ),
  (
    'enterprise',
    'Enterprise',
    'Multi-branch operations with full feature access.',
    15000,
    'USD',
    '/month',
    '["Everything in Professional","Multi-branch support","Advanced queue alerts","Custom branding","API access","Dedicated account manager","SLA guarantee"]'::jsonb,
    'Choose Enterprise',
    false,
    true,
    3
  )
on conflict (id) do update
set
  name = excluded.name,
  description = excluded.description,
  amount = excluded.amount,
  currency = excluded.currency,
  period_label = excluded.period_label,
  features = excluded.features,
  cta = excluded.cta,
  highlighted = excluded.highlighted,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order,
  updated_at = now();

create table if not exists public.billing_plan_prices (
  id uuid primary key default gen_random_uuid(),
  plan_id text not null references public.billing_plans(id) on delete cascade,
  currency text not null,
  amount integer not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint billing_plan_prices_currency_check check (char_length(currency) = 3),
  constraint billing_plan_prices_amount_check check (amount >= 0),
  unique (plan_id, currency)
);

-- Seed multi-currency rows (minor units)
insert into public.billing_plan_prices (plan_id, currency, amount, is_active)
values
  ('starter', 'NGN', 7500000, true),
  ('starter', 'USD', 5000, true),
  ('starter', 'EUR', 1800, true),
  ('starter', 'GBP', 1600, true),
  ('starter', 'KES', 250000, true),
  ('starter', 'ZAR', 36000, true),
  ('starter', 'GHS', 26000, true),

  ('professional', 'NGN', 15000000, true),
  ('professional', 'USD', 10000, true),
  ('professional', 'EUR', 4500, true),
  ('professional', 'GBP', 4000, true),
  ('professional', 'KES', 650000, true),
  ('professional', 'ZAR', 92000, true),
  ('professional', 'GHS', 71000, true),

  ('enterprise', 'NGN', 22500000, true),
  ('enterprise', 'USD', 15000, true),
  ('enterprise', 'EUR', 10900, true),
  ('enterprise', 'GBP', 9800, true),
  ('enterprise', 'KES', 1550000, true),
  ('enterprise', 'ZAR', 230000, true),
  ('enterprise', 'GHS', 185000, true)
on conflict (plan_id, currency) do update
set amount = excluded.amount,
    is_active = excluded.is_active,
    updated_at = now();

alter table public.company_requests
add column if not exists selected_currency text not null default 'USD';

alter table public.company_requests
drop constraint if exists company_requests_selected_currency_check;

alter table public.company_requests
add constraint company_requests_selected_currency_check check (char_length(selected_currency) = 3);

alter table public.billing_plan_prices enable row level security;

create policy "Anyone can view active plan prices" on public.billing_plan_prices
for select to anon, authenticated
using (is_active = true or public.has_role(auth.uid(), 'super_admin'));

create policy "Super admins can manage plan prices" on public.billing_plan_prices
for all to authenticated
using (public.has_role(auth.uid(), 'super_admin'))
with check (public.has_role(auth.uid(), 'super_admin'));

-- <<< END 20260330133000_multicurrency_plan_prices.sql

-- >>> BEGIN 20260330152000_paystack_only_enforcement.sql
-- Enforce Paystack-only processing across billing tables

update public.platform_payment_settings
set default_provider = 'paystack',
    updated_at = now()
where id = 1;

update public.company_requests
set payment_provider = 'paystack'
where payment_provider is distinct from 'paystack';

update public.payment_transactions
set provider = 'paystack'
where provider is distinct from 'paystack';

update public.organization_subscriptions
set payment_provider = 'paystack'
where payment_provider is distinct from 'paystack';

alter table public.platform_payment_settings
drop constraint if exists platform_payment_settings_provider_check;

alter table public.platform_payment_settings
add constraint platform_payment_settings_provider_check check (default_provider = 'paystack');

alter table public.company_requests
drop constraint if exists company_requests_payment_provider_check;

alter table public.company_requests
add constraint company_requests_payment_provider_check check (payment_provider = 'paystack');

alter table public.payment_transactions
drop constraint if exists payment_transactions_provider_check;

alter table public.payment_transactions
add constraint payment_transactions_provider_check check (provider = 'paystack');

alter table public.organization_subscriptions
drop constraint if exists organization_subscriptions_payment_provider_check;

alter table public.organization_subscriptions
add constraint organization_subscriptions_payment_provider_check check (payment_provider = 'paystack');

-- <<< END 20260330152000_paystack_only_enforcement.sql

-- >>> BEGIN 20260401100000_admin_cms_paystack_settings.sql
-- ============================================================
-- CONSOLIDATED: Billing, Payments, CMS, Paystack Settings
-- Merges all payment migrations into one self-contained file
-- Safe to run on a fresh DB or one with partial migrations
-- ============================================================

-- â”€â”€â”€ 1. company_requests: add billing columns â”€â”€â”€
alter table public.company_requests
  add column if not exists selected_plan text not null default 'professional',
  add column if not exists selected_currency text not null default 'USD',
  add column if not exists paystack_reference text,
  add column if not exists payment_status text not null default 'unpaid',
  add column if not exists payment_amount integer not null default 0,
  add column if not exists payment_currency text not null default 'USD',
  add column if not exists paid_at timestamptz,
  add column if not exists payment_metadata jsonb not null default '{}'::jsonb,
  add column if not exists payment_provider text not null default 'paystack',
  add column if not exists payment_reference text;

alter table public.company_requests
  drop constraint if exists company_requests_selected_plan_check;
alter table public.company_requests
  add constraint company_requests_selected_plan_check check (
    selected_plan in ('starter', 'professional', 'enterprise')
  );

alter table public.company_requests
  drop constraint if exists company_requests_payment_status_check;
alter table public.company_requests
  add constraint company_requests_payment_status_check check (
    payment_status in ('unpaid', 'initialized', 'paid', 'failed', 'abandoned')
  );

alter table public.company_requests
  drop constraint if exists company_requests_payment_provider_check;
alter table public.company_requests
  add constraint company_requests_payment_provider_check check (
    payment_provider = 'paystack'
  );

create unique index if not exists company_requests_paystack_reference_key
  on public.company_requests(paystack_reference)
  where paystack_reference is not null;

create unique index if not exists company_requests_payment_reference_key
  on public.company_requests(payment_reference)
  where payment_reference is not null;

-- â”€â”€â”€ 2. payment_transactions â”€â”€â”€
create table if not exists public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  request_id uuid references public.company_requests(id) on delete cascade,
  paystack_reference text not null unique,
  plan_id text not null,
  amount integer not null,
  currency text not null,
  status text not null,
  gateway_message text,
  paid_at timestamptz,
  raw_response jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payment_transactions_plan_id_check check (
    plan_id in ('starter', 'professional', 'enterprise')
  )
);

alter table public.payment_transactions
  add column if not exists provider text not null default 'paystack',
  add column if not exists payment_reference text,
  add column if not exists gross_amount integer not null default 0,
  add column if not exists commission_amount integer not null default 0,
  add column if not exists net_amount integer not null default 0,
  add column if not exists gateway_fee integer not null default 0;

update public.payment_transactions
set
  payment_reference = coalesce(payment_reference, paystack_reference),
  gross_amount = case when gross_amount = 0 then amount else gross_amount end,
  net_amount = case when net_amount = 0 then amount else net_amount end
where true;

alter table public.payment_transactions
  drop constraint if exists payment_transactions_provider_check;
alter table public.payment_transactions
  add constraint payment_transactions_provider_check check (provider = 'paystack');

create unique index if not exists payment_transactions_payment_reference_key
  on public.payment_transactions(payment_reference)
  where payment_reference is not null;

alter table public.payment_transactions enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'payment_transactions' and policyname = 'Company request owner can view payments') then
    create policy "Company request owner can view payments" on public.payment_transactions
    for select to authenticated
    using (
      exists (
        select 1 from public.company_requests cr
        where cr.id = request_id and cr.user_id = auth.uid()
      )
      or public.has_role(auth.uid(), 'super_admin')
    );
  end if;
end $$;

-- â”€â”€â”€ 3. organization_subscriptions â”€â”€â”€
create table if not exists public.organization_subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null unique references public.organizations(id) on delete cascade,
  request_id uuid references public.company_requests(id) on delete set null,
  plan_id text not null,
  status text not null default 'active',
  amount integer not null,
  currency text not null,
  current_period_start timestamptz not null default now(),
  current_period_end timestamptz,
  next_billing_at timestamptz,
  paystack_reference text,
  paystack_customer_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_subscriptions_plan_id_check check (
    plan_id in ('starter', 'professional', 'enterprise')
  ),
  constraint organization_subscriptions_status_check check (
    status in ('active', 'past_due', 'canceled', 'trialing')
  )
);

alter table public.organization_subscriptions
  add column if not exists payment_provider text not null default 'paystack',
  add column if not exists payment_reference text;

alter table public.organization_subscriptions
  drop constraint if exists organization_subscriptions_payment_provider_check;
alter table public.organization_subscriptions
  add constraint organization_subscriptions_payment_provider_check check (payment_provider = 'paystack');

alter table public.organization_subscriptions enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'organization_subscriptions' and policyname = 'Admins can view org subscriptions') then
    create policy "Admins can view org subscriptions" on public.organization_subscriptions
    for select to authenticated
    using (
      public.has_role(auth.uid(), 'super_admin')
      or organization_id = public.get_user_org(auth.uid())
    );
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'organization_subscriptions' and policyname = 'Super admins can manage org subscriptions') then
    create policy "Super admins can manage org subscriptions" on public.organization_subscriptions
    for all to authenticated
    using (public.has_role(auth.uid(), 'super_admin'))
    with check (public.has_role(auth.uid(), 'super_admin'));
  end if;
end $$;

-- â”€â”€â”€ 4. billing_plans â”€â”€â”€
create table if not exists public.billing_plans (
  id text primary key,
  name text not null,
  description text not null,
  amount integer not null,
  currency text not null default 'USD',
  period_label text not null default '/month',
  features jsonb not null default '[]'::jsonb,
  cta text not null default 'Choose Plan',
  highlighted boolean not null default false,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint billing_plans_amount_check check (amount >= 0)
);

insert into public.billing_plans (
  id, name, description, amount, currency, period_label, features, cta, highlighted, is_active, sort_order
)
values
  (
    'starter', 'Starter',
    'Perfect for small businesses with a single location.',
    5000, 'USD', '/month',
    '["1 service counter","Up to 3 services","Basic queue display","Token generation","Email support"]'::jsonb,
    'Choose Starter', false, true, 1
  ),
  (
    'professional', 'Professional',
    'For growing businesses needing advanced queue management.',
    10000, 'USD', '/month',
    '["Unlimited counters","Unlimited services","Priority queuing (VIP/Urgent)","Audio announcements","Analytics & reports","Thermal ticket printing","Staff management","Priority support"]'::jsonb,
    'Choose Professional', true, true, 2
  ),
  (
    'enterprise', 'Enterprise',
    'Multi-branch operations with full feature access.',
    15000, 'USD', '/month',
    '["Everything in Professional","Multi-branch support","Advanced queue alerts","Custom branding","API access","Dedicated account manager","SLA guarantee"]'::jsonb,
    'Choose Enterprise', false, true, 3
  )
on conflict (id) do update
set
  name = excluded.name,
  description = excluded.description,
  amount = excluded.amount,
  currency = excluded.currency,
  period_label = excluded.period_label,
  features = excluded.features,
  cta = excluded.cta,
  highlighted = excluded.highlighted,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order,
  updated_at = now();

alter table public.billing_plans enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'billing_plans' and policyname = 'Anyone can view active billing plans') then
    create policy "Anyone can view active billing plans" on public.billing_plans
    for select to anon, authenticated
    using (is_active = true or public.has_role(auth.uid(), 'super_admin'));
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'billing_plans' and policyname = 'Super admins can manage billing plans') then
    create policy "Super admins can manage billing plans" on public.billing_plans
    for all to authenticated
    using (public.has_role(auth.uid(), 'super_admin'))
    with check (public.has_role(auth.uid(), 'super_admin'));
  end if;
end $$;

-- â”€â”€â”€ 5. platform_payment_settings â”€â”€â”€
create table if not exists public.platform_payment_settings (
  id integer primary key default 1,
  default_provider text not null default 'paystack',
  commission_type text not null default 'percentage',
  commission_value numeric(8,4) not null default 2.5000,
  commission_flat_amount integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_payment_settings_singleton check (id = 1),
  constraint platform_payment_settings_commission_type_check check (commission_type in ('percentage', 'flat')),
  constraint platform_payment_settings_commission_value_check check (commission_value >= 0),
  constraint platform_payment_settings_commission_flat_amount_check check (commission_flat_amount >= 0)
);

-- Drop old provider check that allowed flutterwave, add paystack-only
alter table public.platform_payment_settings
  drop constraint if exists platform_payment_settings_provider_check;
alter table public.platform_payment_settings
  add constraint platform_payment_settings_provider_check check (default_provider = 'paystack');

insert into public.platform_payment_settings (id)
values (1)
on conflict (id) do nothing;

-- Add Paystack admin-configurable columns
alter table public.platform_payment_settings
  add column if not exists paystack_public_key text,
  add column if not exists paystack_secret_key text,
  add column if not exists paystack_callback_url text,
  add column if not exists paystack_test_mode boolean not null default true;

alter table public.platform_payment_settings enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'platform_payment_settings' and policyname = 'Authenticated can view payment settings') then
    create policy "Authenticated can view payment settings" on public.platform_payment_settings
      for select to authenticated using (true);
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'platform_payment_settings' and policyname = 'Super admins can manage payment settings') then
    create policy "Super admins can manage payment settings" on public.platform_payment_settings
      for all to authenticated
      using (public.has_role(auth.uid(), 'super_admin'))
      with check (public.has_role(auth.uid(), 'super_admin'));
  end if;
end $$;

-- â”€â”€â”€ 6. site_content (CMS) â”€â”€â”€
create table if not exists public.site_content (
  id text primary key,
  section text not null,
  label text not null,
  content_type text not null default 'text',
  value text not null default '',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint site_content_type_check check (content_type in ('text', 'json', 'html', 'number'))
);

alter table public.site_content enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'site_content' and policyname = 'Anyone can read site content') then
    create policy "Anyone can read site content" on public.site_content
      for select to anon, authenticated using (true);
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'site_content' and policyname = 'Super admins can manage site content') then
    create policy "Super admins can manage site content" on public.site_content
      for all to authenticated
      using (public.has_role(auth.uid(), 'super_admin'))
      with check (public.has_role(auth.uid(), 'super_admin'));
  end if;
end $$;

-- â”€â”€â”€ 7. Seed default site content â”€â”€â”€
insert into public.site_content (id, section, label, content_type, value, sort_order)
values
  ('hero_title', 'hero', 'Hero Title', 'text', 'Eliminate Waiting Lines with Smart Queue Management', 1),
  ('hero_subtitle', 'hero', 'Hero Subtitle', 'text', 'Transform customer flow using self-service kiosks, live display boards, and powerful staff dashboards. Deliver a seamless digital queue experience that customers love.', 2),
  ('hero_badge', 'hero', 'Hero Badge Text', 'text', 'Built for modern service centers', 3),
  ('hero_cta_primary', 'hero', 'Primary CTA Text', 'text', 'Start Free Trial', 4),
  ('hero_cta_secondary', 'hero', 'Secondary CTA Text', 'text', 'Request Demo', 5),
  ('hero_stat_1_value', 'hero', 'Stat 1 Value', 'text', '47%', 6),
  ('hero_stat_1_label', 'hero', 'Stat 1 Label', 'text', 'Faster Service', 7),
  ('hero_stat_2_value', 'hero', 'Stat 2 Value', 'text', '99.9%', 8),
  ('hero_stat_2_label', 'hero', 'Stat 2 Label', 'text', 'Uptime', 9),
  ('hero_stat_3_value', 'hero', 'Stat 3 Value', 'text', '10K+', 10),
  ('hero_stat_3_label', 'hero', 'Stat 3 Label', 'text', 'Tokens / Day', 11),
  ('brand_name', 'brand', 'Brand Name', 'text', 'Smart Queue', 1),
  ('brand_tagline', 'brand', 'Brand Tagline', 'text', 'Queue Management SaaS', 2),
  ('brand_letter', 'brand', 'Brand Letter (Icon)', 'text', 'Q', 3),
  ('features_title', 'features', 'Features Section Title', 'text', 'Everything You Need to Manage Queues', 1),
  ('features_subtitle', 'features', 'Features Section Subtitle', 'text', 'From self-service kiosks to real-time analytics â€” a complete toolkit for modern queue management.', 2),
  ('features_list', 'features', 'Feature Cards (JSON Array)', 'json', '[{"title":"Self-Service Kiosk","description":"Touchscreen interface for instant service selection and token generation with thermal printing.","icon":"ScanLine"},{"title":"Live Queue Display","description":"Real-time display boards with audio announcements and multi-counter support.","icon":"MonitorSmartphone"},{"title":"Staff Dashboard","description":"Call, recall, skip, transfer tokens. Full queue control from an intuitive panel.","icon":"LayoutDashboard"},{"title":"Analytics & Reports","description":"Track peak hours, waiting times, and service trends with exportable reports.","icon":"BarChart3"},{"title":"Mobile Queue via QR","description":"Customers scan QR to join queue remotely and track position from their phone.","icon":"QrCode"},{"title":"Audio Announcements","description":"Text-to-speech system announces token numbers and counter assignments automatically.","icon":"Volume2"},{"title":"Thermal Ticket Printing","description":"Print queue tickets with token, QR code, service info and estimated wait time.","icon":"Printer"},{"title":"Smart Notifications","description":"In-app reminders and display alerts as a customer''s turn approaches.","icon":"Bell"},{"title":"Priority Queuing","description":"VIP, elderly, and urgent case prioritization with intelligent queue ordering.","icon":"Zap"}]', 3),
  ('how_it_works_title', 'how_it_works', 'Section Title', 'text', 'How It Works', 1),
  ('how_it_works_subtitle', 'how_it_works', 'Section Subtitle', 'text', 'Simple 4-step process from arrival to service completion.', 2),
  ('how_it_works_steps', 'how_it_works', 'Steps (JSON Array)', 'json', '[{"step":"01","title":"Customer selects service","description":"Visitors choose the required service at a self-service kiosk in seconds."},{"step":"02","title":"Token is generated","description":"A smart digital token is generated instantly with queue priority rules."},{"step":"03","title":"Staff calls customer","description":"Staff dashboard shows the next token and allows quick customer calling."},{"step":"04","title":"Display updates live","description":"Queue display screens update in real-time for transparent waiting."}]', 3),
  ('testimonials_title', 'testimonials', 'Section Title', 'text', 'Loved by Teams Everywhere', 1),
  ('testimonials_list', 'testimonials', 'Testimonials (JSON Array)', 'json', '[{"quote":"Smart Queue reduced our average wait times by 52%. Customers love the transparency of knowing exactly where they are in the queue.","author":"Sarah Mitchell","role":"Operations Manager, City Hospital","rating":5},{"quote":"The kiosk interface is incredibly intuitive. Our elderly customers can use it without any assistance, and the priority queue is a game changer.","author":"James Rodriguez","role":"Branch Manager, Metro Bank","rating":5},{"quote":"Setting up was painless. Within an hour, we had our entire service center running on Smart Queue with real-time displays on every floor.","author":"Priya Sharma","role":"COO, TechServ Solutions","rating":5}]', 2),
  ('trusted_by_label', 'trusted_by', 'Section Label', 'text', 'Trusted by service centers worldwide', 1),
  ('trusted_by_list', 'trusted_by', 'Trusted By Items (JSON Array)', 'json', '["ðŸ¥ Hospitals","ðŸ¦ Banks","ðŸ›ï¸ Government","ðŸ“¡ Telecom","ðŸ›« Airlines","ðŸŽ“ Universities"]', 2),
  ('cta_title', 'cta', 'CTA Title', 'text', 'Ready to Transform Your Customer Experience?', 1),
  ('cta_subtitle', 'cta', 'CTA Subtitle', 'text', 'Join thousands of service centers already using Smart Queue. Start your free 14-day trial today.', 2),
  ('cta_primary', 'cta', 'CTA Primary Button', 'text', 'Start Free Trial', 3),
  ('cta_secondary', 'cta', 'CTA Secondary Button', 'text', 'Contact Sales', 4),
  ('pricing_title', 'pricing', 'Pricing Title', 'text', 'Plans That Scale With You', 1),
  ('pricing_subtitle', 'pricing', 'Pricing Subtitle', 'text', 'Transparent monthly pricing built for serious operations.', 2),
  ('pricing_badges', 'pricing', 'Pricing Trust Badges (JSON Array)', 'json', '["No hidden fees","Cancel anytime","Instant activation after approval"]', 3),
  ('footer_description', 'footer', 'Footer Description', 'text', 'The modern queue management platform for customer-centric businesses.', 1),
  ('footer_copyright', 'footer', 'Copyright Text', 'text', 'Smart Queue. All rights reserved.', 2),
  ('saas_title', 'saas', 'SaaS Section Title', 'text', 'Enterprise-Ready Cloud Platform', 1),
  ('saas_subtitle', 'saas', 'SaaS Section Subtitle', 'text', 'Built for scale with multi-tenant architecture, automatic backups, and global deployment capability. Designed for reliability and security.', 2),
  ('saas_features', 'saas', 'SaaS Feature Cards (JSON Array)', 'json', '[{"title":"Multi-Tenant Architecture","text":"Securely manage multiple organizations from one platform."},{"title":"Cloud Infrastructure","text":"99.9% uptime with global CDN and automatic scaling."},{"title":"Enterprise Security","text":"SOC 2 compliant with role-based access control."},{"title":"Global Deployment","text":"Deploy kiosks and displays across unlimited branches."}]', 3)
on conflict (id) do nothing;

-- â”€â”€â”€ 8. Seed default billing_plan_prices for USD â”€â”€â”€
create table if not exists public.billing_plan_prices (
  id uuid primary key default gen_random_uuid(),
  plan_id text not null references public.billing_plans(id) on delete cascade,
  currency text not null,
  amount integer not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(plan_id, currency)
);

alter table public.billing_plan_prices enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'billing_plan_prices' and policyname = 'Anyone can view active prices') then
    create policy "Anyone can view active prices" on public.billing_plan_prices
    for select to anon, authenticated
    using (is_active = true);
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'billing_plan_prices' and policyname = 'Super admins can manage prices') then
    create policy "Super admins can manage prices" on public.billing_plan_prices
    for all to authenticated
    using (public.has_role(auth.uid(), 'super_admin'))
    with check (public.has_role(auth.uid(), 'super_admin'));
  end if;
end $$;

insert into public.billing_plan_prices (plan_id, currency, amount, is_active)
values
  ('starter',      'USD', 5000,  true),
  ('professional', 'USD', 10000, true),
  ('enterprise',   'USD', 15000, true)
on conflict (plan_id, currency) do nothing;

-- <<< END 20260401100000_admin_cms_paystack_settings.sql

-- >>> BEGIN 20260401120000_company_admin_settings.sql
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Migration: Company admin self-management
-- Adds service pricing, currency, and company profile fields
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- 1. Add price columns to services table
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS price integer DEFAULT 0,                    -- in minor units (cents/kobo)
  ADD COLUMN IF NOT EXISTS price_currency text DEFAULT 'USD',
  ADD COLUMN IF NOT EXISTS show_price_on_kiosk boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS estimated_duration_minutes integer DEFAULT 15,
  ADD COLUMN IF NOT EXISTS description text;

-- 2. Add settings columns to organizations table
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS contact_email text,
  ADD COLUMN IF NOT EXISTS contact_phone text,
  ADD COLUMN IF NOT EXISTS timezone text DEFAULT 'UTC',
  ADD COLUMN IF NOT EXISTS default_currency text DEFAULT 'USD',
  ADD COLUMN IF NOT EXISTS logo_url text,
  ADD COLUMN IF NOT EXISTS primary_color text DEFAULT '#7c3aed',
  ADD COLUMN IF NOT EXISTS website_url text,
  ADD COLUMN IF NOT EXISTS address text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- 3. Grant company admins RLS access to update their own organization
-- (organizations table should already have RLS; just ensure update policy exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organizations' AND policyname = 'company_admin_update_own_org'
  ) THEN
    CREATE POLICY company_admin_update_own_org ON public.organizations
      FOR UPDATE
      USING (
        id IN (
          SELECT organization_id FROM public.user_roles
          WHERE user_id = auth.uid() AND role IN ('company_admin', 'super_admin')
        )
      );
  END IF;
END $$;

-- 4. Grant company admins RLS access to update services prices
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'services' AND policyname = 'company_admin_update_services'
  ) THEN
    CREATE POLICY company_admin_update_services ON public.services
      FOR UPDATE
      USING (
        organization_id IN (
          SELECT organization_id FROM public.user_roles
          WHERE user_id = auth.uid() AND role IN ('company_admin', 'super_admin')
        )
      );
  END IF;
END $$;

-- <<< END 20260401120000_company_admin_settings.sql

-- >>> BEGIN 20260405120000_feature_enhancement.sql
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Migration: Full feature enhancement
-- Adds org kiosk/notification settings, token tracking columns,
-- appointments, activity_logs, device_health tables
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- 1. Organization kiosk & notification settings
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS kiosk_idle_message text DEFAULT 'Welcome! Tap to get started',
  ADD COLUMN IF NOT EXISTS kiosk_ads jsonb DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS auto_print_enabled boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS display_ads jsonb DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS sms_enabled boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS whatsapp_enabled boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS notification_before_turns integer DEFAULT 3,
  ADD COLUMN IF NOT EXISTS avg_service_time_minutes integer DEFAULT 5;

-- 2. Token tracking enhancements
ALTER TABLE public.tokens
  ADD COLUMN IF NOT EXISTS staff_notes text,
  ADD COLUMN IF NOT EXISTS served_at timestamptz,
  ADD COLUMN IF NOT EXISTS completed_at timestamptz,
  ADD COLUMN IF NOT EXISTS actual_wait_minutes integer,
  ADD COLUMN IF NOT EXISTS notification_sent boolean DEFAULT false;

-- 3. Appointments table
CREATE TABLE IF NOT EXISTS public.appointments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  service_id uuid NOT NULL REFERENCES public.services(id) ON DELETE CASCADE,
  customer_name text NOT NULL,
  customer_phone text,
  customer_email text,
  appointment_date date NOT NULL,
  appointment_time time NOT NULL,
  status text DEFAULT 'scheduled' CHECK (status IN ('scheduled','checked_in','completed','cancelled','no_show')),
  notes text,
  token_id uuid REFERENCES public.tokens(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- 4. Activity / audit log
CREATE TABLE IF NOT EXISTS public.activity_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  user_id uuid,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id text,
  details jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);

-- 5. Device health monitoring
CREATE TABLE IF NOT EXISTS public.device_health (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  device_type text NOT NULL CHECK (device_type IN ('kiosk','display','printer')),
  device_name text,
  status text DEFAULT 'online' CHECK (status IN ('online','offline','warning')),
  last_heartbeat timestamptz DEFAULT now(),
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);

-- 6. RLS on new tables
ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_health ENABLE ROW LEVEL SECURITY;

-- Appointments: org members can read, company_admin can write
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='appointments' AND policyname='appointments_select_org') THEN
    CREATE POLICY appointments_select_org ON public.appointments FOR SELECT
      USING (organization_id IN (SELECT organization_id FROM public.user_roles WHERE user_id = auth.uid()));
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='appointments' AND policyname='appointments_insert_org') THEN
    CREATE POLICY appointments_insert_org ON public.appointments FOR INSERT
      WITH CHECK (organization_id IN (
        SELECT organization_id FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('company_admin','super_admin')
      ));
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='appointments' AND policyname='appointments_update_org') THEN
    CREATE POLICY appointments_update_org ON public.appointments FOR UPDATE
      USING (organization_id IN (
        SELECT organization_id FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('company_admin','super_admin','staff')
      ));
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='appointments' AND policyname='appointments_delete_org') THEN
    CREATE POLICY appointments_delete_org ON public.appointments FOR DELETE
      USING (organization_id IN (
        SELECT organization_id FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('company_admin','super_admin')
      ));
  END IF;
END $$;

-- Activity logs: org members can read, anyone can insert
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='activity_logs' AND policyname='activity_logs_select_org') THEN
    CREATE POLICY activity_logs_select_org ON public.activity_logs FOR SELECT
      USING (organization_id IN (SELECT organization_id FROM public.user_roles WHERE user_id = auth.uid()));
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='activity_logs' AND policyname='activity_logs_insert_org') THEN
    CREATE POLICY activity_logs_insert_org ON public.activity_logs FOR INSERT
      WITH CHECK (organization_id IN (SELECT organization_id FROM public.user_roles WHERE user_id = auth.uid()));
  END IF;
END $$;

-- Device health: org members can read/write
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='device_health' AND policyname='device_health_select_org') THEN
    CREATE POLICY device_health_select_org ON public.device_health FOR SELECT
      USING (organization_id IN (SELECT organization_id FROM public.user_roles WHERE user_id = auth.uid()));
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='device_health' AND policyname='device_health_all_org') THEN
    CREATE POLICY device_health_all_org ON public.device_health FOR ALL
      USING (TRUE) WITH CHECK (TRUE);
  END IF;
END $$;

-- Index for faster token lookups
CREATE INDEX IF NOT EXISTS idx_tokens_org_status ON public.tokens (organization_id, status);
CREATE INDEX IF NOT EXISTS idx_tokens_served_at ON public.tokens (served_at) WHERE served_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointments_org_date ON public.appointments (organization_id, appointment_date);
CREATE INDEX IF NOT EXISTS idx_activity_logs_org ON public.activity_logs (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_health_org ON public.device_health (organization_id, device_type);

-- <<< END 20260405120000_feature_enhancement.sql

-- >>> BEGIN 20260429110000_add_unlimited_free_plan.sql
-- Add an unlimited free plan and ensure it is available in all active currencies.

insert into public.billing_plans (
  id,
  name,
  description,
  amount,
  currency,
  period_label,
  features,
  cta,
  highlighted,
  is_active,
  sort_order
)
values (
  'free',
  'Free',
  'Unlimited access with no payment required.',
  0,
  'USD',
  '/forever',
  '["Unlimited counters", "Unlimited services", "Unlimited tokens", "Queue display and kiosk", "Staff management", "Reports and analytics"]'::jsonb,
  'Start Free',
  true,
  true,
  0
)
on conflict (id) do update set
  name = excluded.name,
  description = excluded.description,
  amount = excluded.amount,
  currency = excluded.currency,
  period_label = excluded.period_label,
  features = excluded.features,
  cta = excluded.cta,
  highlighted = excluded.highlighted,
  is_active = true,
  sort_order = excluded.sort_order,
  updated_at = now();

insert into public.billing_plan_prices (plan_id, currency, amount, is_active)
select 'free', c.currency, 0, true
from (
  select 'USD'::text as currency
  union
  select distinct currency from public.billing_plan_prices
) as c
on conflict (plan_id, currency) do update set
  amount = excluded.amount,
  is_active = true,
  updated_at = now();

-- <<< END 20260429110000_add_unlimited_free_plan.sql

