-- Public, aggregate-only ratings. Individual review text and buyer identities remain private.
create or replace function public.get_public_product_review_summaries(p_product_ids uuid[])
returns table(product_id uuid, average_rating numeric, review_count bigint)
language sql
stable
security definer
set search_path = ''
as $function$
  select r.product_id,
         round(avg(r.rating)::numeric, 1) as average_rating,
         count(*)::bigint as review_count
  from public.product_reviews r
  where p_product_ids is not null
    and cardinality(p_product_ids) <= 100
    and r.product_id = any(p_product_ids)
  group by r.product_id;
$function$;

create or replace function public.get_public_driver_rating_summaries(p_driver_ids uuid[])
returns table(driver_id uuid, average_rating numeric, rating_count bigint)
language sql
stable
security definer
set search_path = ''
as $function$
  select r.driver_id,
         round(avg(r.rating)::numeric, 1) as average_rating,
         count(*)::bigint as rating_count
  from public.driver_ratings r
  where p_driver_ids is not null
    and cardinality(p_driver_ids) <= 100
    and r.driver_id = any(p_driver_ids)
  group by r.driver_id;
$function$;

revoke all on function public.get_public_product_review_summaries(uuid[]) from public, anon, authenticated;
revoke all on function public.get_public_driver_rating_summaries(uuid[]) from public, anon, authenticated;
grant execute on function public.get_public_product_review_summaries(uuid[]) to anon, authenticated;
grant execute on function public.get_public_driver_rating_summaries(uuid[]) to anon, authenticated;
