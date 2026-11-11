-- Voucher and promotion foundation for Pasar Hanakau.
-- Existing orders and settings are preserved; new discount columns default to zero.
create table if not exists public.promo_vouchers (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  description text not null default '',
  discount_type text not null check (discount_type in ('percentage','fixed')),
  discount_value numeric(14,2) not null check (discount_value > 0),
  min_subtotal numeric(14,2) not null default 0 check (min_subtotal >= 0),
  max_discount numeric(14,2),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  usage_limit integer,
  per_buyer_limit integer not null default 1 check (per_buyer_limit > 0),
  active boolean not null default false,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint promo_vouchers_code_format check (code = upper(trim(code)) and code ~ '^[A-Z0-9_-]{3,40}$'),
  constraint promo_vouchers_max_discount_nonnegative check (max_discount is null or max_discount > 0),
  constraint promo_vouchers_usage_limit_positive check (usage_limit is null or usage_limit > 0),
  constraint promo_vouchers_date_range check (ends_at is null or ends_at > starts_at)
);

create table if not exists public.voucher_redemptions (
  id uuid primary key default gen_random_uuid(),
  voucher_id uuid not null references public.promo_vouchers(id),
  buyer_id uuid not null references public.profiles(id),
  checkout_group_id uuid not null,
  discount_amount numeric(14,2) not null check (discount_amount >= 0),
  order_ids uuid[] not null default '{}',
  redeemed_at timestamptz not null default now(),
  unique (voucher_id, checkout_group_id)
);

alter table public.orders
  add column if not exists voucher_id uuid references public.promo_vouchers(id),
  add column if not exists discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  add column if not exists checkout_group_id uuid;

alter table public.orders drop constraint if exists orders_total_discount_check;
alter table public.orders add constraint orders_total_discount_check
  check (total = subtotal + delivery_fee - discount_amount and total >= 0);

create index if not exists promo_vouchers_active_window_idx on public.promo_vouchers (active, starts_at, ends_at);
create index if not exists voucher_redemptions_buyer_idx on public.voucher_redemptions (buyer_id, redeemed_at desc);
create index if not exists orders_voucher_id_idx on public.orders (voucher_id);

alter table public.promo_vouchers enable row level security;
alter table public.voucher_redemptions enable row level security;
revoke all on public.promo_vouchers from anon, authenticated;
grant select, insert, update, delete on public.promo_vouchers to authenticated;
grant select on public.promo_vouchers to anon;
revoke all on public.voucher_redemptions from anon, authenticated;
grant select on public.voucher_redemptions to authenticated;

drop policy if exists "Active vouchers are visible" on public.promo_vouchers;
create policy "Active vouchers are visible" on public.promo_vouchers
for select to anon, authenticated
using (active = true and starts_at <= now() and (ends_at is null or ends_at > now()));

drop policy if exists "Admins manage vouchers" on public.promo_vouchers;
create policy "Admins manage vouchers" on public.promo_vouchers
for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Buyers view own voucher redemptions" on public.voucher_redemptions;
create policy "Buyers view own voucher redemptions" on public.voucher_redemptions
for select to authenticated using (buyer_id = (select auth.uid()) or public.is_admin());

drop trigger if exists set_promo_vouchers_updated_at on public.promo_vouchers;
create trigger set_promo_vouchers_updated_at before update on public.promo_vouchers
for each row execute function public.set_updated_at();

comment on table public.promo_vouchers is 'Kode voucher dan promo Pasar Hanakau; hanya admin yang dapat mengelola.';
comment on table public.voucher_redemptions is 'Riwayat pemakaian voucher yang dibuat secara atomik oleh checkout server.';
