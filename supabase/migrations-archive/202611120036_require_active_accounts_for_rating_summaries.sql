-- Limit aggregate rating RPCs to active signed-in accounts.
-- These SECURITY DEFINER functions expose aggregate-only values and intentionally
-- remain executable by authenticated users; inactive/suspended accounts are denied.
CREATE OR REPLACE FUNCTION public.get_public_driver_rating_summaries(p_driver_ids uuid[])
RETURNS TABLE(driver_id uuid, average_rating numeric, rating_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT r.driver_id,
         round(avg(r.rating)::numeric, 1) AS average_rating,
         count(*)::bigint AS rating_count
  FROM public.driver_ratings r
  WHERE public.current_user_is_active()
    AND p_driver_ids IS NOT NULL
    AND cardinality(p_driver_ids) <= 100
    AND r.driver_id = ANY(p_driver_ids)
  GROUP BY r.driver_id;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_product_review_summaries(p_product_ids uuid[])
RETURNS TABLE(product_id uuid, average_rating numeric, review_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT r.product_id,
         round(avg(r.rating)::numeric, 1) AS average_rating,
         count(*)::bigint AS review_count
  FROM public.product_reviews r
  WHERE public.current_user_is_active()
    AND p_product_ids IS NOT NULL
    AND cardinality(p_product_ids) <= 100
    AND r.product_id = ANY(p_product_ids)
  GROUP BY r.product_id;
$function$;
