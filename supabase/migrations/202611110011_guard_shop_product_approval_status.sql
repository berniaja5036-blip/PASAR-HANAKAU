-- Only administrators may change shop/product approval status.
create or replace function public.guard_shop_product_approval_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $ph$
begin
  if new.status is distinct from old.status
     and not coalesce(public.is_admin(), false) then
    raise exception 'Hanya admin yang dapat mengubah status persetujuan toko atau produk.';
  end if;
  return new;
end;
$ph$;

revoke all on function public.guard_shop_product_approval_status() from public, anon, authenticated;

drop trigger if exists shops_approval_status_guard on public.shops;
create trigger shops_approval_status_guard
before update of status on public.shops
for each row execute function public.guard_shop_product_approval_status();

drop trigger if exists products_approval_status_guard on public.products;
create trigger products_approval_status_guard
before update of status on public.products
for each row execute function public.guard_shop_product_approval_status();

-- Seller-created shops must remain pending until admin approval.
drop policy if exists shops_seller_insert_own on public.shops;
create policy shops_seller_insert_own
on public.shops
for insert
to authenticated
with check (
  owner_id = (select auth.uid())
  and status = 'pending'
  and (select public.current_user_has_role('seller'))
);
