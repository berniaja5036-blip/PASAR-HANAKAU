-- Keep public catalogue reads available to signed-out visitors without
-- exposing the SECURITY DEFINER admin helper to the anon role.
--
-- Anonymous visitors may read only approved shops, active products from
-- approved shops, and enabled payment methods. Signed-in users retain the
-- same public visibility plus their own shop rows and admin visibility.

drop policy if exists products_public_catalog_read on public.products;

create policy products_public_catalog_read_anon
on public.products for select to anon
using (
  status = 'active'
  and exists (
    select 1 from public.shops s
    where s.id = products.shop_id and s.status = 'approved'
  )
);

create policy products_authenticated_catalog_read
on public.products for select to authenticated
using (
  (
    status = 'active'
    and exists (
      select 1 from public.shops s
      where s.id = products.shop_id and s.status = 'approved'
    )
  )
  or exists (
    select 1 from public.shops s
    where s.id = products.shop_id and s.owner_id = (select auth.uid())
  )
  or (select public.is_admin())
);

drop policy if exists shops_public_approved_read on public.shops;

create policy shops_public_approved_read_anon
on public.shops for select to anon
using (status = 'approved');

create policy shops_authenticated_read
on public.shops for select to authenticated
using (
  status = 'approved'
  or owner_id = (select auth.uid())
  or (select public.is_admin())
);

drop policy if exists marketplace_payment_methods_public_enabled_read
on public.marketplace_payment_methods;

create policy marketplace_payment_methods_public_enabled_read_anon
on public.marketplace_payment_methods for select to anon
using (enabled = true);

create policy marketplace_payment_methods_authenticated_read
on public.marketplace_payment_methods for select to authenticated
using (enabled = true or (select public.is_admin()));

revoke execute on function public.is_admin() from anon;
