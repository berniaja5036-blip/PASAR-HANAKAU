begin;

create table public.driver_presence (
  user_id uuid primary key references public.driver_profiles(id) on delete cascade,
  last_seen_at timestamptz not null default pg_catalog.now()
);

alter table public.driver_presence enable row level security;
grant select, insert, update on public.driver_presence to authenticated;

create policy driver_presence_read_self_or_admin
  on public.driver_presence
  for select
  to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

create policy driver_presence_insert_approved_self
  on public.driver_presence
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.driver_profiles dp
      where dp.id = (select auth.uid())
        and dp.approval_status = 'approved'
    )
  );

create policy driver_presence_update_approved_self
  on public.driver_presence
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.driver_profiles dp
      where dp.id = (select auth.uid())
        and dp.approval_status = 'approved'
    )
  );

create or replace function public.set_driver_presence_timestamp()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.last_seen_at := now();
  return new;
end;
$$;

revoke all on function public.set_driver_presence_timestamp() from public, anon, authenticated;

create trigger set_driver_presence_timestamp_before_write
  before insert or update on public.driver_presence
  for each row execute function public.set_driver_presence_timestamp();

create policy deliveries_buyer_seller_assigned_read
  on public.deliveries
  for select
  to authenticated
  using (
    driver_id is not null
    and (
      exists (
        select 1 from public.orders o
        where o.id = deliveries.order_id
          and o.buyer_id = (select auth.uid())
      )
      or public.seller_can_read_order(deliveries.order_id)
    )
  );

create policy driver_profiles_assigned_order_read
  on public.driver_profiles
  for select
  to authenticated
  using (
    exists (
      select 1 from public.deliveries d
      where d.driver_id = driver_profiles.id
    )
  );

create or replace function public.admin_assign_delivery(p_order_id uuid, p_driver_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order_status text;
  v_delivery_status text;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'Hanya admin yang dapat menugaskan driver.';
  end if;

  -- Lock the driver row so two concurrent assignments cannot give one
  -- driver two active deliveries at the same time.
  perform 1
  from public.driver_profiles dp
  where dp.id = p_driver_id
    and dp.approval_status = 'approved'
  for update;

  if not found then
    raise exception 'Akun driver belum disetujui atau tidak ditemukan.';
  end if;

  select status into v_order_status
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Pesanan tidak ditemukan.';
  end if;
  if v_order_status <> 'ready_for_pickup' then
    raise exception 'Pesanan harus berstatus Siap dijemput sebelum ditugaskan.';
  end if;

  select status into v_delivery_status
  from public.deliveries
  where order_id = p_order_id
  for update;

  if not found then
    raise exception 'Data pengiriman untuk pesanan ini tidak ditemukan.';
  end if;
  if v_delivery_status not in ('waiting','assigned') then
    raise exception 'Pengiriman sudah berjalan dan tidak dapat ditugaskan ulang.';
  end if;

  if exists (
    select 1
    from public.deliveries d
    where d.driver_id = p_driver_id
      and d.order_id <> p_order_id
      and d.status in ('assigned','picked_up')
  ) then
    raise exception 'Driver sedang bertugas pada pesanan lain. Pilih driver yang standby.';
  end if;

  update public.deliveries
     set driver_id = p_driver_id,
         status = 'assigned',
         assigned_at = pg_catalog.now()
   where order_id = p_order_id;
end;
$function$;

revoke all on function public.admin_assign_delivery(uuid,uuid) from public, anon;
grant execute on function public.admin_assign_delivery(uuid,uuid) to authenticated;

commit;