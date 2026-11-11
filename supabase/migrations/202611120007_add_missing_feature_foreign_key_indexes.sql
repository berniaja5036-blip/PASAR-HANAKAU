create index if not exists buyer_wishlist_product_id_idx on public.buyer_wishlist(product_id);
create index if not exists driver_ratings_buyer_id_idx on public.driver_ratings(buyer_id);
create index if not exists product_reviews_buyer_id_idx on public.product_reviews(buyer_id);
create index if not exists promo_vouchers_created_by_idx on public.promo_vouchers(created_by);
