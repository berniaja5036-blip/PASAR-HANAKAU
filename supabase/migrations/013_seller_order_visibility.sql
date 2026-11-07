-- Pasar Hanakau: penjual hanya dapat melihat pesanan yang berisi produk dari tokonya.
-- Data alamat pembeli dan pesanan toko lain tidak ditampilkan pada panel penjual.

create or replace function public.seller_can_read_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.order_items oi
    join public.shops s on s.id = oi.shop_id
    where oi.order_id = p_order_id
      and s.owner_id = (select auth.uid())
      and (select public.current_user_has_role('seller'))
  );
$$;

revoke all on function public.seller_can_read_order(uuid) from public, anon;
grant execute on function public.seller_can_read_order(uuid) to authenticated;

drop policy if exists orders_seller_own_shop_read on public.orders;
create policy orders_seller_own_shop_read
on public.orders for select to authenticated
using ((select public.seller_can_read_order(id)));

drop policy if exists order_items_seller_own_shop_read on public.order_items;
create policy order_items_seller_own_shop_read
on public.order_items for select to authenticated
using (
  exists (
    select 1
    from public.shops s
    where s.id = order_items.shop_id
      and s.owner_id = (select auth.uid())
  )
  and (select public.current_user_has_role('seller'))
);

grant select on public.orders, public.order_items to authenticated;
