drop policy if exists product_reviews_buyer_insert_verified on public.product_reviews;
create policy product_reviews_buyer_insert_verified
on public.product_reviews
for insert
to authenticated
with check (
  product_reviews.buyer_id = (select auth.uid())
  and exists (
    select 1 from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where oi.id = product_reviews.order_item_id
      and oi.product_id = product_reviews.product_id
      and oi.shop_id = product_reviews.shop_id
      and o.buyer_id = product_reviews.buyer_id
      and o.status = 'delivered'
      and o.buyer_received_at is not null
  )
);

drop policy if exists driver_ratings_buyer_insert_verified on public.driver_ratings;
create policy driver_ratings_buyer_insert_verified
on public.driver_ratings
for insert
to authenticated
with check (
  driver_ratings.buyer_id = (select auth.uid())
  and exists (
    select 1 from public.orders o
    join public.deliveries d on d.order_id = o.id
    where o.id = driver_ratings.order_id
      and o.buyer_id = driver_ratings.buyer_id
      and o.status = 'delivered'
      and o.buyer_received_at is not null
      and d.driver_id = driver_ratings.driver_id
      and d.status = 'delivered'
  )
);
