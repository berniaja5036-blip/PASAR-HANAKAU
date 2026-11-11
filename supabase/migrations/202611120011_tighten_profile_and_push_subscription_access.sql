-- Allow users to update only their own non-privileged profile fields.
revoke update on table public.profiles from authenticated;
grant update (full_name, phone, full_address) on table public.profiles to authenticated;

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self
on public.profiles
for update
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

-- Driver application documents must be stored under the applicant's own private folder.
drop policy if exists driver_applications_insert_own on public.driver_applications;
create policy driver_applications_insert_own
on public.driver_applications
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and status = 'pending'
  and ktp_image_path is not null
  and ktp_image_path like (select auth.uid())::text || '/%'
  and face_image_path is not null
  and face_image_path like (select auth.uid())::text || '/%'
);

-- Seller application pickup coordinates must be valid before the admin can approve the shop.
drop policy if exists seller_applications_insert_own on public.seller_applications;
create policy seller_applications_insert_own
on public.seller_applications
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and status = 'pending'
  and pickup_latitude between -90 and 90
  and pickup_longitude between -180 and 180
);

-- Public profile avatar paths may only point to the owner's folder.
drop policy if exists user_public_profiles_insert_own on public.user_public_profiles;
create policy user_public_profiles_insert_own
on public.user_public_profiles
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and (
    avatar_path is null
    or avatar_path like (select auth.uid())::text || '/%'
  )
);

-- Prevent approving or retaining an approved shop with invalid pickup coordinates.
create or replace function public.guard_shop_product_approval_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.status is distinct from old.status
     and not coalesce(public.is_admin(), false) then
    raise exception 'Hanya admin yang dapat mengubah status persetujuan toko atau produk.';
  end if;

  if tg_table_name = 'shops'
     and new.status = 'approved'
     and (
       new.pickup_latitude is null
       or new.pickup_longitude is null
       or new.pickup_latitude not between -90 and 90
       or new.pickup_longitude not between -180 and 180
     ) then
    raise exception 'Toko harus memiliki titik penjemputan yang valid sebelum disetujui.';
  end if;

  return new;
end;
$function$;

-- Push subscriptions are managed only by the authenticated Edge Function using service_role.
revoke all on table public.push_subscriptions from anon, authenticated;
