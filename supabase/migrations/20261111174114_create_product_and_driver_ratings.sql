create table if not exists public.product_reviews (
  id uuid primary key default gen_random_uuid(),
  order_item_id uuid not null unique references public.order_items(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  shop_id uuid not null references public.shops(id) on delete restrict,
  buyer_id uuid not null references auth.users(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  review_text text check (review_text is null or char_length(review_text) <= 1000),
  created_at timestamptz not null default now()
);
create index if not exists product_reviews_product_created_idx on public.product_reviews(product_id, created_at desc);
create index if not exists product_reviews_shop_created_idx on public.product_reviews(shop_id, created_at desc);
alter table public.product_reviews enable row level security;
grant select on public.product_reviews to anon, authenticated;
grant insert on public.product_reviews to authenticated;
create policy product_reviews_public_read on public.product_reviews for select to anon, authenticated using (true);
create policy product_reviews_buyer_insert_verified on public.product_reviews for insert to authenticated
with check (
  buyer_id = (select auth.uid())
  and exists (
    select 1 from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where oi.id = order_item_id
      and oi.product_id = product_id
      and oi.shop_id = shop_id
      and o.buyer_id = (select auth.uid())
      and o.status = 'delivered'
      and o.buyer_received_at is not null
  )
);

create table if not exists public.driver_ratings (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  driver_id uuid not null references auth.users(id) on delete cascade,
  buyer_id uuid not null references auth.users(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  review_text text check (review_text is null or char_length(review_text) <= 1000),
  created_at timestamptz not null default now()
);
create index if not exists driver_ratings_driver_created_idx on public.driver_ratings(driver_id, created_at desc);
alter table public.driver_ratings enable row level security;
grant select, insert on public.driver_ratings to authenticated;
create policy driver_ratings_participant_read on public.driver_ratings for select to authenticated
using (buyer_id = (select auth.uid()) or driver_id = (select auth.uid()) or (select public.is_admin()));
create policy driver_ratings_buyer_insert_verified on public.driver_ratings for insert to authenticated
with check (
  buyer_id = (select auth.uid())
  and exists (
    select 1 from public.orders o
    join public.deliveries d on d.order_id = o.id
    where o.id = order_id
      and o.buyer_id = (select auth.uid())
      and o.status = 'delivered'
      and o.buyer_received_at is not null
      and d.driver_id = driver_id
      and d.status = 'delivered'
  )
);