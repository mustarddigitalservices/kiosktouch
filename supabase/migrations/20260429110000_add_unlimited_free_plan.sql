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
