create table if not exists public.marketplace_payment_methods (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  bank_name text not null,
  account_name text not null,
  account_number text not null,
  instructions text,
  enabled boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint marketplace_payment_methods_label_check check (length(trim(label)) between 2 and 60),
  constraint marketplace_payment_methods_bank_check check (length(trim(bank_name)) between 2 and 80),
  constraint marketplace_payment_methods_account_name_check check (length(trim(account_name)) between 2 and 120),
  constraint marketplace_payment_methods_account_number_check check (length(trim(account_number)) between 4 and 40)
);
alter table public.marketplace_payment_methods enable row level security;
grant select on public.marketplace_payment_methods to anon, authenticated;
grant insert, update, delete on public.marketplace_payment_methods to authenticated;
create policy marketplace_payment_methods_public_enabled_read on public.marketplace_payment_methods
for select to anon, authenticated using (enabled = true or (select is_admin()));
create policy marketplace_payment_methods_admin_manage on public.marketplace_payment_methods
for all to authenticated using ((select is_admin())) with check ((select is_admin()));
alter table public.marketplace_ads add column if not exists payment_reference text, add column if not exists payment_submitted_at timestamptz;
create policy marketplace_ads_seller_submit_payment_reference on public.marketplace_ads
for update to authenticated using (owner_id = (select auth.uid()) and status = 'awaiting_payment')
with check (owner_id = (select auth.uid()) and status = 'awaiting_payment');
create or replace function public.seller_submit_marketplace_ad_payment(p_ad_id uuid,p_payment_reference text)
returns void language plpgsql security invoker set search_path = '' as $$
begin
 if p_payment_reference is null or length(trim(p_payment_reference)) < 4 or length(trim(p_payment_reference)) > 120 then raise exception 'Referensi pembayaran harus 4 sampai 120 karakter'; end if;
 update public.marketplace_ads set payment_reference=trim(p_payment_reference),payment_submitted_at=now(),updated_at=now()
 where id=p_ad_id and owner_id=(select auth.uid()) and status='awaiting_payment';
 if not found then raise exception 'Tagihan tidak ditemukan atau tidak dapat diperbarui'; end if;
end; $$;
grant execute on function public.seller_submit_marketplace_ad_payment(uuid,text) to authenticated;
