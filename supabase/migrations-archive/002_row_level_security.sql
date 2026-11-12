-- Pasar Hanakau: tahap 2 - kebijakan akses dasar (RLS)
-- Terapkan setelah 001_initial_schema.sql.
-- Semua pemeriksaan peran dilakukan di server; pengguna tidak dapat menaikkan perannya sendiri.

create or replace function public.current_user_has_role(required_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = required_role
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.current_user_has_role('admin');
$$;

revoke all on function public.current_user_has_role(text) from public;
revoke all on function public.is_admin() from public;
grant execute on function public.current_user_has_role(text) to authenticated;
grant execute on function public.is_admin() to authenticated;

-- Buat profil otomatis untuk setiap akun baru; role selalu buyer, bukan dari metadata pengguna.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    'buyer'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Profil: pengguna hanya dapat membaca profilnya sendiri; admin dapat membaca semua.
drop policy if exists profiles_select_self_or_admin on public.profiles;
create policy profiles_select_self_or_admin
on public.profiles for select to authenticated
using (id = (select auth.uid()) or (select public.is_admin()));

-- Cegah perubahan role melalui API. Pengguna hanya boleh mengubah nama dan nomor telepon sendiri.
revoke update on table public.profiles from anon, authenticated;
grant update (full_name, phone) on table public.profiles to authenticated;

-- Toko yang disetujui dapat dilihat publik. Pemilik melihat dan mengelola tokonya sendiri.
drop policy if exists shops_public_approved_read on public.shops;
create policy shops_public_approved_read
on public.shops for select to anon, authenticated
using (status = 'approved' or owner_id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists shops_seller_insert_own on public.shops;
create policy shops_seller_insert_own
on public.shops for insert to authenticated
with check (
  owner_id = (select auth.uid())
  and (select public.current_user_has_role('seller'))
);

drop policy if exists shops_owner_update_or_admin on public.shops;
create policy shops_owner_update_or_admin
on public.shops for update to authenticated
using (owner_id = (select auth.uid()) or (select public.is_admin()))
with check (owner_id = (select auth.uid()) or (select public.is_admin()));

-- Kategori aktif dapat dilihat publik; hanya admin yang mengelolanya.
drop policy if exists categories_public_active_read on public.categories;
create policy categories_public_active_read
on public.categories for select to anon, authenticated
using (is_active = true or (select public.is_admin()));

drop policy if exists categories_admin_manage on public.categories;
create policy categories_admin_manage
on public.categories for all to authenticated
using ((select public.is_admin()))
with check ((select public.is_admin()));

-- Produk aktif dari toko yang disetujui terlihat publik.
-- Penjual hanya dapat melihat/mengelola produk milik tokonya.
drop policy if exists products_public_catalog_read on public.products;
create policy products_public_catalog_read
on public.products for select to anon, authenticated
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

drop policy if exists products_seller_insert_own_shop on public.products;
create policy products_seller_insert_own_shop
on public.products for insert to authenticated
with check (
  exists (
    select 1 from public.shops s
    where s.id = products.shop_id
      and s.owner_id = (select auth.uid())
      and s.status = 'approved'
  )
  and (select public.current_user_has_role('seller'))
);

drop policy if exists products_seller_update_own_shop on public.products;
create policy products_seller_update_own_shop
on public.products for update to authenticated
using (
  exists (
    select 1 from public.shops s
    where s.id = products.shop_id and s.owner_id = (select auth.uid())
  )
  or (select public.is_admin())
)
with check (
  exists (
    select 1 from public.shops s
    where s.id = products.shop_id and s.owner_id = (select auth.uid())
  )
  or (select public.is_admin())
);

drop policy if exists products_seller_delete_own_shop on public.products;
create policy products_seller_delete_own_shop
on public.products for delete to authenticated
using (
  exists (
    select 1 from public.shops s
    where s.id = products.shop_id and s.owner_id = (select auth.uid())
  )
  or (select public.is_admin())
);

-- Pesanan dan item pesanan sengaja belum diberi izin tulis dari aplikasi.
-- Pembuatan pesanan harus memakai fungsi server yang memvalidasi harga, stok, dan total.
drop policy if exists orders_buyer_seller_admin_read on public.orders;
create policy orders_buyer_seller_admin_read
on public.orders for select to authenticated
using (
  buyer_id = (select auth.uid())
  or (select public.is_admin())
);

drop policy if exists order_items_buyer_seller_admin_read on public.order_items;
create policy order_items_buyer_seller_admin_read
on public.order_items for select to authenticated
using (
  (select public.is_admin())
  or exists (
    select 1 from public.orders o
    where o.id = order_items.order_id and o.buyer_id = (select auth.uid())
  )
);

-- Driver hanya dapat membaca profil driver miliknya sendiri; admin dapat membaca semua.
drop policy if exists driver_profiles_self_or_admin_read on public.driver_profiles;
create policy driver_profiles_self_or_admin_read
on public.driver_profiles for select to authenticated
using (id = (select auth.uid()) or (select public.is_admin()));

-- Driver hanya dapat melihat pengiriman yang ditugaskan kepadanya; admin dapat melihat semua.
drop policy if exists deliveries_assigned_driver_or_admin_read on public.deliveries;
create policy deliveries_assigned_driver_or_admin_read
on public.deliveries for select to authenticated
using (
  driver_id = (select auth.uid())
  or (select public.is_admin())
);

-- Penugasan dan perubahan status pengiriman dilakukan melalui proses server/admin
-- pada tahap berikutnya; tidak ada izin tulis langsung dari klien.
