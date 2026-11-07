-- Pasar Hanakau: izinkan penjual mengubah detail produk tokonya,
-- termasuk produk aktif, tanpa memberi hak mengubah status persetujuan.
revoke update on table public.products from authenticated;
grant update (name, description, price, stock, category_id, image_path)
on table public.products to authenticated;

drop policy if exists products_seller_update_own_shop on public.products;
create policy products_seller_update_own_shop
on public.products for update to authenticated
using (
  exists (
    select 1 from public.shops s
    where s.id = products.shop_id
      and s.owner_id = (select auth.uid())
      and s.status = 'approved'
  )
  and (select public.current_user_has_role('seller'))
  or (select public.is_admin())
)
with check (
  exists (
    select 1 from public.shops s
    where s.id = products.shop_id
      and s.owner_id = (select auth.uid())
      and s.status = 'approved'
  )
  and (select public.current_user_has_role('seller'))
  or (select public.is_admin())
);
