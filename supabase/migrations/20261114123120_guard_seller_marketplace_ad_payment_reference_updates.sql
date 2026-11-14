create or replace function public.guard_marketplace_ad_seller_payment_update()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
 if not (select is_admin()) then
  if old.owner_id is distinct from (select auth.uid()) or old.status <> 'awaiting_payment'
   or new.id is distinct from old.id or new.shop_id is distinct from old.shop_id or new.owner_id is distinct from old.owner_id
   or new.product_id is distinct from old.product_id or new.ad_type is distinct from old.ad_type or new.title is distinct from old.title
   or new.caption is distinct from old.caption or new.image_url is distinct from old.image_url or new.cta_label is distinct from old.cta_label
   or new.requested_days is distinct from old.requested_days or new.quoted_price is distinct from old.quoted_price
   or new.status is distinct from old.status or new.review_note is distinct from old.review_note
   or new.reviewed_by is distinct from old.reviewed_by or new.reviewed_at is distinct from old.reviewed_at
   or new.starts_at is distinct from old.starts_at or new.ends_at is distinct from old.ends_at
   or new.created_at is distinct from old.created_at then
   raise exception 'Penjual hanya dapat mengirim referensi pembayaran untuk tagihannya sendiri';
  end if;
 end if;
 return new;
end; $$;
create trigger guard_marketplace_ad_seller_payment_update before update on public.marketplace_ads
for each row execute function public.guard_marketplace_ad_seller_payment_update();
