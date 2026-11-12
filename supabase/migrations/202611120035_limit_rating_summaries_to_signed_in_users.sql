-- Rating aggregates are only needed by signed-in marketplace users.
revoke execute on function public.get_public_product_review_summaries(uuid[]) from anon;
revoke execute on function public.get_public_driver_rating_summaries(uuid[]) from anon;
