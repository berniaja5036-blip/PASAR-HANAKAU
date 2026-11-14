create table if not exists public.marketplace_ads (
 id uuid primary key default gen_random_uuid(),
 shop_id uuid not null references public.shops(id) on delete cascade,
 owner_id uuid not null references public.profiles(id) on delete cascade,
 product_id uuid references public.products(id) on delete set null,
 ad_type text not null check (ad_type in ('banner','product')),
 title text not null check (char_length(btrim(title)) between 3 and 120),
 caption text not null default '' check (char_length(caption) <= 240),
 image_url text,
 cta_label text not null default 'Lihat Produk' check (char_length(cta_label) <= 30),
 requested_days integer not null default 7 check (requested_days in (3,7,15,30)),
 quoted_price numeric(12,2),
 status text not null default 'pending' check (status in ('pending','awaiting_payment','approved','rejected','paused')),
 review_note text,
 reviewed_by uuid references public.profiles(id),
 reviewed_at timestamptz,
 starts_at timestamptz,
 ends_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint marketplace_ads_banner_image_check check (ad_type <> 'banner' or (image_url is not null and image_url ~* '^https?://')),
 constraint marketplace_ads_product_check check (ad_type <> 'product' or product_id is not null),
 constraint marketplace_ads_dates_check check (ends_at is null or starts_at is null or ends_at > starts_at)
);
create index if not exists marketplace_ads_public_idx on public.marketplace_ads(status, starts_at, ends_at, ad_type);
create index if not exists marketplace_ads_owner_idx on public.marketplace_ads(owner_id, created_at desc);
alter table public.marketplace_ads enable row level security;
grant select on public.marketplace_ads to anon, authenticated;
grant insert, update, delete on public.marketplace_ads to authenticated;
create policy marketplace_ads_public_active_read on public.marketplace_ads for select to anon, authenticated using (status = 'approved' and starts_at <= now() and ends_at > now());
create policy marketplace_ads_seller_read_own on public.marketplace_ads for select to authenticated using (owner_id = (select auth.uid()));
create policy marketplace_ads_seller_insert_own on public.marketplace_ads for insert to authenticated with check (owner_id = (select auth.uid()) and status = 'pending' and quoted_price is null and starts_at is null and ends_at is null and exists (select 1 from public.shops s where s.id = marketplace_ads.shop_id and s.owner_id = (select auth.uid()) and s.status = 'approved') and exists (select 1 from public.products p where p.id = marketplace_ads.product_id and p.shop_id = marketplace_ads.shop_id and p.status = 'active') and (select current_user_has_role('seller')));
create policy marketplace_ads_admin_all on public.marketplace_ads for all to authenticated using ((select is_admin())) with check ((select is_admin()));