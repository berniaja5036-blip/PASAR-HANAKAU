-- Pasar Hanakau: fondasi lokasi toko, ongkir, konfirmasi pembayaran driver,
-- dan komisi seller 2% yang ditagihkan bulanan.
-- Jalankan sekali di Supabase SQL Editor setelah migrasi 016.
-- Tarif ongkir sengaja NONAKTIF sampai admin mengatur angka tarif yang disepakati.

alter table public.shops
  add column if not exists pickup_latitude numeric(9,6),
  add column if not exists pickup_longitude numeric(9,6);

alter table public.orders
  add column if not exists pickup_latitude numeric(9,6),
  add column if not exists pickup_longitude numeric(9,6),
  add column if not exists delivery_latitude numeric(9,6),
  add column if not exists delivery_longitude numeric(9,6),
  add column if not exists route_distance_m integer,
  add column if not exists delivery_fee_payment_status text not null default 'unpaid',
  add column if not exists delivery_fee_payment_method text,
  add column if not exists driver_fee_confirmed_at timestamptz,
  add column if not exists buyer_fee_confirmed_at timestamptz,
  add column if not exists delivery_fee_paid_at timestamptz,
  add column if not exists delivery_fee_dispute_note text;

update public.orders
   set delivery_fee_payment_status = 'not_required'
 where delivery_fee = 0
   and delivery_fee_payment_status = 'unpaid';

do $ph$
begin
  if not exists (select 1 from pg_constraint where conname = 'orders_delivery_fee_payment_status_check') then
    alter table public.orders add constraint orders_delivery_fee_payment_status_check
      check (delivery_fee_payment_status in ('not_required','unpaid','driver_confirmed','buyer_confirmed','confirmed','disputed'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'orders_delivery_fee_payment_method_check') then
    alter table public.orders add constraint orders_delivery_fee_payment_method_check
      check (delivery_fee_payment_method is null or delivery_fee_payment_method in ('cash','transfer'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'orders_route_distance_check') then
    alter table public.orders add constraint orders_route_distance_check
      check (route_distance_m is null or route_distance_m >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'shops_pickup_latitude_check') then
    alter table public.shops add constraint shops_pickup_latitude_check
      check (pickup_latitude is null or pickup_latitude between -90 and 90);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'shops_pickup_longitude_check') then
    alter table public.shops add constraint shops_pickup_longitude_check
      check (pickup_longitude is null or pickup_longitude between -180 and 180);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'orders_delivery_latitude_check') then
    alter table public.orders add constraint orders_delivery_latitude_check
      check (delivery_latitude is null or delivery_latitude between -90 and 90);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'orders_delivery_longitude_check') then
    alter table public.orders add constraint orders_delivery_longitude_check
      check (delivery_longitude is null or delivery_longitude between -180 and 180);
  end if;
end;
$ph$;

create or replace function public.sync_delivery_fee_payment_status()
returns trigger
language plpgsql
set search_path = ''
as $ph$
begin
  if new.delivery_fee <= 0 then
    new.delivery_fee_payment_status := 'not_required';
    new.delivery_fee_payment_method := null;
    new.driver_fee_confirmed_at := null;
    new.buyer_fee_confirmed_at := null;
    new.delivery_fee_paid_at := null;
  elsif tg_op = 'INSERT' or new.delivery_fee is distinct from old.delivery_fee then
    new.delivery_fee_payment_status := 'unpaid';
    new.delivery_fee_payment_method := null;
    new.driver_fee_confirmed_at := null;
    new.buyer_fee_confirmed_at := null;
    new.delivery_fee_paid_at := null;
  end if;
  return new;
end;
$ph$;

drop trigger if exists orders_sync_delivery_fee_payment_status on public.orders;
create trigger orders_sync_delivery_fee_payment_status
before insert or update of delivery_fee on public.orders
for each row execute function public.sync_delivery_fee_payment_status();

create table if not exists public.delivery_fee_settings (
  id boolean primary key default true check (id),
  enabled boolean not null default false,
  base_fee numeric(14,2) not null default 0 check (base_fee >= 0),
  per_km_fee numeric(14,2) not null default 0 check (per_km_fee >= 0),
  minimum_fee numeric(14,2) not null default 0 check (minimum_fee >= 0),
  max_distance_km numeric(8,2) not null default 15 check (max_distance_km > 0),
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

insert into public.delivery_fee_settings(id) values (true)
on conflict (id) do nothing;

alter table public.delivery_fee_settings enable row level security;
grant select on public.delivery_fee_settings to authenticated;
drop policy if exists delivery_fee_settings_read_authenticated on public.delivery_fee_settings;
create policy delivery_fee_settings_read_authenticated
on public.delivery_fee_settings for select to authenticated
using (true);

create or replace function public.admin_update_delivery_fee_settings(
  p_enabled boolean,
  p_base_fee numeric,
  p_per_km_fee numeric,
  p_minimum_fee numeric,
  p_max_distance_km numeric
)
returns void
language plpgsql
security definer
set search_path = ''
as $ph$
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'Hanya admin yang dapat mengatur tarif pengantaran.';
  end if;
  if coalesce(p_base_fee,-1) < 0 or coalesce(p_per_km_fee,-1) < 0
     or coalesce(p_minimum_fee,-1) < 0 or coalesce(p_max_distance_km,0) <= 0 then
    raise exception 'Nilai tarif dan batas jarak tidak valid.';
  end if;
  if p_enabled and p_per_km_fee <= 0 then
    raise exception 'Tarif per kilometer harus lebih dari nol sebelum ongkir diaktifkan.';
  end if;
  update public.delivery_fee_settings
     set enabled = p_enabled,
         base_fee = p_base_fee,
         per_km_fee = p_per_km_fee,
         minimum_fee = p_minimum_fee,
         max_distance_km = p_max_distance_km,
         updated_by = (select auth.uid()),
         updated_at = now()
   where id = true;
end;
$ph$;
revoke all on function public.admin_update_delivery_fee_settings(boolean,numeric,numeric,numeric,numeric) from public, anon;
grant execute on function public.admin_update_delivery_fee_settings(boolean,numeric,numeric,numeric,numeric) to authenticated;

create table if not exists public.seller_commission_settings (
  id boolean primary key default true check (id),
  rate_percent numeric(5,2) not null default 2.00 check (rate_percent > 0 and rate_percent <= 10),
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);
insert into public.seller_commission_settings(id,rate_percent) values (true,2.00)
on conflict (id) do nothing;
alter table public.seller_commission_settings enable row level security;

create table if not exists public.seller_commission_invoices (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles(id) on delete restrict,
  period_start date not null,
  subtotal_amount numeric(14,2) not null default 0 check (subtotal_amount >= 0),
  commission_amount numeric(14,2) not null default 0 check (commission_amount >= 0),
  status text not null default 'issued'
    check (status in ('issued','payment_submitted','paid')),
  due_date date,
  payment_reference text,
  seller_submitted_at timestamptz,
  admin_note text,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (seller_id,period_start),
  check (extract(day from period_start) = 1)
);

create table if not exists public.seller_commission_entries (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete restrict,
  invoice_id uuid references public.seller_commission_invoices(id) on delete set null,
  seller_id uuid not null references public.profiles(id) on delete restrict,
  shop_id uuid not null references public.shops(id) on delete restrict,
  period_start date not null,
  basis_amount numeric(14,2) not null check (basis_amount >= 0),
  rate_percent numeric(5,2) not null check (rate_percent > 0 and rate_percent <= 10),
  commission_amount numeric(14,2) not null check (commission_amount >= 0),
  status text not null default 'accrued' check (status in ('accrued','invoiced','paid')),
  created_at timestamptz not null default now(),
  check (extract(day from period_start) = 1)
);

create index if not exists seller_commission_entries_seller_period_idx
  on public.seller_commission_entries(seller_id,period_start,status);
create index if not exists seller_commission_invoices_seller_period_idx
  on public.seller_commission_invoices(seller_id,period_start desc);

alter table public.seller_commission_invoices enable row level security;
alter table public.seller_commission_entries enable row level security;
grant select on public.seller_commission_invoices, public.seller_commission_entries to authenticated;

drop policy if exists seller_commission_invoices_read_owner_admin on public.seller_commission_invoices;
create policy seller_commission_invoices_read_owner_admin
on public.seller_commission_invoices for select to authenticated
using (seller_id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists seller_commission_entries_read_owner_admin on public.seller_commission_entries;
create policy seller_commission_entries_read_owner_admin
on public.seller_commission_entries for select to authenticated
using (seller_id = (select auth.uid()) or (select public.is_admin()));

create or replace function public.record_seller_commission_on_delivery()
returns trigger
language plpgsql
security definer
set search_path = ''
as $ph$
declare
  v_rate numeric(5,2);
begin
  if new.status = 'delivered' and old.status is distinct from new.status then
    select rate_percent into v_rate
      from public.seller_commission_settings where id = true;

    insert into public.seller_commission_entries
      (order_id,seller_id,shop_id,period_start,basis_amount,rate_percent,commission_amount)
    select
      new.id,
      s.owner_id,
      oi.shop_id,
      (date_trunc('month',now()))::date,
      sum(oi.line_total),
      coalesce(v_rate,2.00),
      round(sum(oi.line_total) * coalesce(v_rate,2.00) / 100.0,0)
    from public.order_items oi
    join public.shops s on s.id = oi.shop_id
    where oi.order_id = new.id
    group by s.owner_id,oi.shop_id
    on conflict (order_id) do nothing;
  end if;
  return new;
end;
$ph$;

drop trigger if exists orders_record_seller_commission on public.orders;
create trigger orders_record_seller_commission
after update of status on public.orders
for each row execute function public.record_seller_commission_on_delivery();

create or replace function public.admin_generate_monthly_commission_invoices(
  p_period_start date,
  p_due_date date default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $ph$
declare
  v_count integer;
begin
  if not coalesce(public.is_admin(),false) then
    raise exception 'Hanya admin yang dapat menerbitkan tagihan komisi.';
  end if;
  if p_period_start is null or extract(day from p_period_start) <> 1 then
    raise exception 'Periode tagihan harus menggunakan tanggal pertama bulan.';
  end if;
  if p_due_date is not null and p_due_date < p_period_start then
    raise exception 'Tanggal jatuh tempo tidak valid.';
  end if;

  insert into public.seller_commission_invoices
    (seller_id,period_start,subtotal_amount,commission_amount,status,due_date)
  select seller_id,period_start,sum(basis_amount),sum(commission_amount),'issued',p_due_date
  from public.seller_commission_entries
  where period_start = p_period_start and status = 'accrued'
  group by seller_id,period_start
  on conflict (seller_id,period_start) do nothing;

  update public.seller_commission_entries e
     set invoice_id = i.id,status = 'invoiced'
    from public.seller_commission_invoices i
   where i.seller_id = e.seller_id
     and i.period_start = e.period_start
     and e.period_start = p_period_start
     and e.status = 'accrued';

  update public.seller_commission_invoices i
     set subtotal_amount = totals.subtotal_amount,
         commission_amount = totals.commission_amount
    from (
      select invoice_id,sum(basis_amount) as subtotal_amount,sum(commission_amount) as commission_amount
        from public.seller_commission_entries
       where period_start = p_period_start and invoice_id is not null
       group by invoice_id
    ) totals
   where i.id = totals.invoice_id and i.status = 'issued';

  get diagnostics v_count = row_count;
  return v_count;
end;
$ph$;
revoke all on function public.admin_generate_monthly_commission_invoices(date,date) from public, anon;
grant execute on function public.admin_generate_monthly_commission_invoices(date,date) to authenticated;

create or replace function public.seller_submit_commission_payment(
  p_invoice_id uuid,
  p_payment_reference text
)
returns void
language plpgsql
security definer
set search_path = ''
as $ph$
begin
  if not (select public.current_user_has_role('seller')) then
    raise exception 'Hanya akun seller yang dapat mengirim konfirmasi pembayaran komisi.';
  end if;
  if length(trim(coalesce(p_payment_reference,''))) < 4
     or length(trim(coalesce(p_payment_reference,''))) > 120 then
    raise exception 'Nomor referensi transfer harus berisi 4 sampai 120 karakter.';
  end if;
  update public.seller_commission_invoices
     set status = 'payment_submitted',
         payment_reference = trim(p_payment_reference),
         seller_submitted_at = now(),
         admin_note = null
   where id = p_invoice_id
     and seller_id = (select auth.uid())
     and status = 'issued';
  if not found then
    raise exception 'Tagihan tidak ditemukan atau sudah pernah dikirim untuk pemeriksaan.';
  end if;
end;
$ph$;
revoke all on function public.seller_submit_commission_payment(uuid,text) from public, anon;
grant execute on function public.seller_submit_commission_payment(uuid,text) to authenticated;

create or replace function public.admin_review_commission_payment(
  p_invoice_id uuid,
  p_approve boolean,
  p_admin_note text default ''
)
returns void
language plpgsql
security definer
set search_path = ''
as $ph$
declare
  v_invoice public.seller_commission_invoices%rowtype;
begin
  if not coalesce(public.is_admin(),false) then
    raise exception 'Hanya admin yang dapat memverifikasi pembayaran komisi.';
  end if;
  select * into v_invoice
    from public.seller_commission_invoices
   where id = p_invoice_id
   for update;
  if not found or v_invoice.status <> 'payment_submitted' then
    raise exception 'Konfirmasi pembayaran tidak ditemukan atau sudah diproses.';
  end if;

  update public.seller_commission_invoices
     set status = case when p_approve then 'paid' else 'issued' end,
         admin_note = nullif(trim(coalesce(p_admin_note,'')),''),
         reviewed_by = (select auth.uid()),
         reviewed_at = now()
   where id = p_invoice_id;

  if p_approve then
    update public.seller_commission_entries
       set status = 'paid'
     where invoice_id = p_invoice_id;
  end if;
end;
$ph$;
revoke all on function public.admin_review_commission_payment(uuid,boolean,text) from public, anon;
grant execute on function public.admin_review_commission_payment(uuid,boolean,text) to authenticated;

create or replace function public.driver_confirm_delivery_fee(
  p_order_id uuid,
  p_payment_method text
)
returns void
language plpgsql
security definer
set search_path = ''
as $ph$
declare
  v_order public.orders%rowtype;
begin
  if p_payment_method is null or p_payment_method not in ('cash','transfer') then
    raise exception 'Metode pembayaran ongkir harus tunai atau transfer.';
  end if;
  select o.* into v_order
    from public.orders o
    join public.deliveries d on d.order_id = o.id
   where o.id = p_order_id and d.driver_id = (select auth.uid())
   for update of o;
  if not found then
    raise exception 'Pesanan tidak ditemukan untuk driver ini.';
  end if;
  if v_order.status <> 'delivered' or v_order.delivery_fee <= 0 then
    raise exception 'Konfirmasi ongkir hanya tersedia setelah pesanan diterima buyer dan ongkir lebih dari nol.';
  end if;
  if v_order.delivery_fee_payment_status = 'disputed' then
    raise exception 'Pembayaran ongkir sedang diperiksa admin.';
  end if;
  if v_order.driver_fee_confirmed_at is not null then
    raise exception 'Penerimaan ongkir sudah dikonfirmasi.';
  end if;

  update public.orders
     set driver_fee_confirmed_at = now(),
         delivery_fee_payment_method = p_payment_method,
         delivery_fee_payment_status = case
           when buyer_fee_confirmed_at is not null then 'confirmed'
           else 'driver_confirmed'
         end,
         delivery_fee_paid_at = case
           when buyer_fee_confirmed_at is not null then now()
           else null
         end
   where id = p_order_id;
end;
$ph$;
revoke all on function public.driver_confirm_delivery_fee(uuid,text) from public, anon;
grant execute on function public.driver_confirm_delivery_fee(uuid,text) to authenticated;

create or replace function public.buyer_confirm_delivery_fee(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $ph$
declare
  v_order public.orders%rowtype;
begin
  select * into v_order
    from public.orders
   where id = p_order_id and buyer_id = (select auth.uid())
   for update;
  if not found then
    raise exception 'Pesanan tidak ditemukan untuk akun buyer ini.';
  end if;
  if v_order.delivery_fee <= 0 or v_order.status <> 'delivered' then
    raise exception 'Konfirmasi ongkir hanya tersedia setelah pesanan diterima.';
  end if;
  if v_order.delivery_fee_payment_status = 'disputed' then
    raise exception 'Pembayaran ongkir sedang diperiksa admin.';
  end if;
  if v_order.buyer_fee_confirmed_at is not null then
    raise exception 'Konfirmasi buyer sudah tercatat.';
  end if;

  update public.orders
     set buyer_fee_confirmed_at = now(),
         delivery_fee_payment_status = case
           when driver_fee_confirmed_at is not null then 'confirmed'
           else 'buyer_confirmed'
         end,
         delivery_fee_paid_at = case
           when driver_fee_confirmed_at is not null then now()
           else null
         end
   where id = p_order_id;
end;
$ph$;
revoke all on function public.buyer_confirm_delivery_fee(uuid) from public, anon;
grant execute on function public.buyer_confirm_delivery_fee(uuid) to authenticated;

create or replace function public.buyer_report_delivery_fee_dispute(
  p_order_id uuid,
  p_note text
)
returns void
language plpgsql
security definer
set search_path = ''
as $ph$
begin
  if length(trim(coalesce(p_note,''))) < 5 or length(trim(coalesce(p_note,''))) > 500 then
    raise exception 'Keterangan masalah harus berisi 5 sampai 500 karakter.';
  end if;
  update public.orders
     set delivery_fee_payment_status = 'disputed',
         delivery_fee_dispute_note = trim(p_note)
   where id = p_order_id
     and buyer_id = (select auth.uid())
     and status = 'delivered'
     and delivery_fee > 0
     and delivery_fee_payment_status <> 'confirmed';
  if not found then
    raise exception 'Pesanan tidak dapat dilaporkan atau pembayaran sudah dikonfirmasi.';
  end if;
end;
$ph$;
revoke all on function public.buyer_report_delivery_fee_dispute(uuid,text) from public, anon;
grant execute on function public.buyer_report_delivery_fee_dispute(uuid,text) to authenticated;

create or replace function public.admin_resolve_delivery_fee_dispute(
  p_order_id uuid,
  p_mark_paid boolean,
  p_admin_note text
)
returns void
language plpgsql
security definer
set search_path = ''
as $ph$
begin
  if not coalesce(public.is_admin(),false) then
    raise exception 'Hanya admin yang dapat memeriksa sengketa ongkir.';
  end if;
  if length(trim(coalesce(p_admin_note,''))) < 5 or length(trim(coalesce(p_admin_note,''))) > 500 then
    raise exception 'Catatan pemeriksaan harus berisi 5 sampai 500 karakter.';
  end if;
  update public.orders
     set delivery_fee_payment_status = case when p_mark_paid then 'confirmed' else 'unpaid' end,
         delivery_fee_paid_at = case when p_mark_paid then coalesce(delivery_fee_paid_at,now()) else null end,
         delivery_fee_dispute_note = trim(p_admin_note)
   where id = p_order_id and delivery_fee_payment_status = 'disputed';
  if not found then
    raise exception 'Sengketa ongkir tidak ditemukan atau sudah diselesaikan.';
  end if;
end;
$ph$;
revoke all on function public.admin_resolve_delivery_fee_dispute(uuid,boolean,text) from public, anon;
grant execute on function public.admin_resolve_delivery_fee_dispute(uuid,boolean,text) to authenticated;

-- Seluruh perubahan saldo komisi dan konfirmasi ongkir dilakukan melalui RPC
-- agar seller, buyer, driver, dan admin tidak dapat mengubah catatan keuangan langsung.
