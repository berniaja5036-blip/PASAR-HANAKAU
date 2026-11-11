drop policy if exists product_reviews_public_read on public.product_reviews;
drop policy if exists product_reviews_participant_read on public.product_reviews;
create policy product_reviews_participant_read
on public.product_reviews
for select
to authenticated
using (
  product_reviews.buyer_id = (select auth.uid())
  or (select public.is_admin())
  or exists (
    select 1 from public.shops s
    where s.id = product_reviews.shop_id
      and s.owner_id = (select auth.uid())
  )
);
revoke select on public.product_reviews from anon;
grant select on public.product_reviews to authenticated;
