-- Categories: separate public catalogue reads from authenticated/admin reads.
drop policy if exists categories_admin_manage on public.categories;
drop policy if exists categories_public_active_read on public.categories;

create policy categories_anon_active_read
on public.categories for select to anon
using (is_active = true);

create policy categories_authenticated_read
on public.categories for select to authenticated
using (is_active = true or public.is_admin());

create policy categories_admin_insert
on public.categories for insert to authenticated
with check (public.is_admin());

create policy categories_admin_update
on public.categories for update to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy categories_admin_delete
on public.categories for delete to authenticated
using (public.is_admin());

-- Deliveries: one scoped read policy avoids repeated permissive policy evaluation.
drop policy if exists deliveries_assigned_driver_or_admin_read on public.deliveries;
drop policy if exists deliveries_buyer_seller_assigned_read on public.deliveries;

create policy deliveries_read_scoped
on public.deliveries for select to authenticated
using (
  driver_id = (select auth.uid())
  or (select public.is_admin())
  or (
    driver_id is not null
    and public.current_user_can_read_delivery_order(order_id)
  )
);

-- Driver profile visibility is self/admin or a driver assigned to a delivery visible to this user.
drop policy if exists driver_profiles_assigned_order_read on public.driver_profiles;
drop policy if exists driver_profiles_self_or_admin_read on public.driver_profiles;

create policy driver_profiles_read_scoped
on public.driver_profiles for select to authenticated
using (
  id = (select auth.uid())
  or (select public.is_admin())
  or exists (
    select 1 from public.deliveries d
    where d.driver_id = driver_profiles.id
  )
);

-- Order item visibility preserves buyer, seller, admin, and assigned-driver scopes.
drop policy if exists order_items_assigned_driver_read on public.order_items;
drop policy if exists order_items_buyer_seller_admin_read on public.order_items;
drop policy if exists order_items_seller_own_shop_read on public.order_items;

create policy order_items_read_scoped
on public.order_items for select to authenticated
using (
  (select public.is_admin())
  or exists (
    select 1 from public.orders o
    where o.id = order_items.order_id
      and o.buyer_id = (select auth.uid())
  )
  or (
    (select public.current_user_has_role('seller'))
    and exists (
      select 1 from public.shops s
      where s.id = order_items.shop_id
        and s.owner_id = (select auth.uid())
    )
  )
  or public.current_user_is_assigned_driver(order_id)
);

-- Orders: buyer/admin plus assigned driver, without a policy cycle.
drop policy if exists orders_assigned_driver_read on public.orders;
drop policy if exists orders_buyer_seller_admin_read on public.orders;

create policy orders_read_scoped
on public.orders for select to authenticated
using (
  buyer_id = (select auth.uid())
  or (select public.is_admin())
  or public.current_user_is_assigned_driver(id)
);

-- Voucher reads: anon sees only currently active vouchers; admins can see all.
drop policy if exists "Admins manage vouchers" on public.promo_vouchers;
drop policy if exists "Active vouchers are visible" on public.promo_vouchers;

create policy promo_vouchers_anon_active_read
on public.promo_vouchers for select to anon
using (
  active = true
  and starts_at <= now()
  and (ends_at is null or ends_at > now())
);

create policy promo_vouchers_authenticated_read
on public.promo_vouchers for select to authenticated
using (
  (
    active = true
    and starts_at <= now()
    and (ends_at is null or ends_at > now())
  )
  or (select public.is_admin())
);

create policy promo_vouchers_admin_insert
on public.promo_vouchers for insert to authenticated
with check (public.is_admin());

create policy promo_vouchers_admin_update
on public.promo_vouchers for update to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy promo_vouchers_admin_delete
on public.promo_vouchers for delete to authenticated
using (public.is_admin());
