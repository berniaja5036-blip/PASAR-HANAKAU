begin;

do $migration$
begin
  if to_regprocedure('public.current_user_can_read_delivery_order(uuid)') is null then
    raise exception 'Helper pembatas akses pesanan tidak ditemukan; migrasi dihentikan.';
  end if;
end;
$migration$;

drop policy if exists driver_profiles_read_scoped on public.driver_profiles;

create policy driver_profiles_read_scoped
on public.driver_profiles
for select
to authenticated
using (
  id = (select auth.uid())
  or (select public.is_admin())
  or exists (
    select 1
    from public.deliveries d
    where d.driver_id = driver_profiles.id
      and public.current_user_can_read_delivery_order(d.order_id)
  )
);

commit;
