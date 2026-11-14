begin;

create or replace function public.driver_update_delivery_status(
  p_delivery_id uuid,
  p_new_status text,
  p_note text default ''
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_order_id uuid;
  v_delivery_status text;
  v_order_status text;
  v_note text;
begin
  if not public.current_user_is_active() then
    raise exception 'Akun tidak aktif.';
  end if;
  if (select auth.uid()) is null then
    raise exception 'Silakan masuk terlebih dahulu.';
  end if;
  if not exists (
    select 1 from public.profiles p
    join public.driver_profiles dp on dp.id = p.id
    where p.id = (select auth.uid())
      and p.role = 'driver'
      and dp.approval_status = 'approved'
  ) then
    raise exception 'Akun driver belum disetujui atau peran akun tidak sesuai.';
  end if;
  if p_new_status is null or p_new_status not in ('picked_up','delivered') then
    raise exception 'Status pengiriman tidak valid.';
  end if;

  v_note := nullif(pg_catalog.btrim(coalesce(p_note,'')), '');
  if pg_catalog.length(coalesce(v_note,'')) > 500 then
    raise exception 'Catatan pengiriman maksimal 500 karakter.';
  end if;

  select d.order_id, d.status, o.status
    into v_order_id, v_delivery_status, v_order_status
  from public.deliveries d
  join public.orders o on o.id = d.order_id
  where d.id = p_delivery_id and d.driver_id = (select auth.uid())
  for update of d, o;

  if not found then
    raise exception 'Tugas pengiriman tidak ditemukan untuk akun driver ini.';
  end if;

  if p_new_status = 'picked_up' then
    if v_delivery_status <> 'assigned' or v_order_status <> 'ready_for_pickup' then
      raise exception 'Pesanan belum siap dijemput atau status tugas tidak sesuai.';
    end if;
    update public.deliveries
       set status = 'picked_up', picked_up_at = pg_catalog.now(), pickup_notes = v_note
     where id = p_delivery_id;
    update public.orders set status = 'picked_up' where id = v_order_id;
  else
    if v_delivery_status <> 'picked_up' or v_order_status <> 'picked_up' then
      raise exception 'Pesanan harus dijemput terlebih dahulu.';
    end if;
    update public.deliveries
       set status = 'delivered', delivered_at = pg_catalog.now(), delivery_notes = v_note
     where id = p_delivery_id;
    update public.orders set status = 'delivered' where id = v_order_id;
  end if;
end;
$function$;

create or replace function public.driver_confirm_delivery_fee(
  p_order_id uuid,
  p_payment_method text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_order public.orders%rowtype;
begin
  if not public.current_user_is_active() then
    raise exception 'Akun tidak aktif.';
  end if;
  if (select auth.uid()) is null then
    raise exception 'Silakan masuk terlebih dahulu.';
  end if;
  if not exists (
    select 1 from public.profiles p
    join public.driver_profiles dp on dp.id = p.id
    where p.id = (select auth.uid())
      and p.role = 'driver'
      and dp.approval_status = 'approved'
  ) then
    raise exception 'Akun driver belum disetujui atau peran akun tidak sesuai.';
  end if;
  if p_payment_method is null or p_payment_method not in ('cash','transfer') then
    raise exception 'Metode pembayaran ongkir harus tunai atau transfer.';
  end if;

  select o.* into v_order
    from public.orders o
    join public.deliveries d on d.order_id = o.id
   where o.id = p_order_id and d.driver_id = (select auth.uid())
   for update of o;

  if not found then
    raise exception 'Pesanan tidak ditemukan untuk driver ini.';
  end if;
  if v_order.status <> 'delivered' or v_order.delivery_fee <= 0
     or v_order.buyer_received_at is null then
    raise exception 'Konfirmasi ongkir hanya tersedia setelah barang diterima pembeli dan ongkir lebih dari nol.';
  end if;
  if v_order.delivery_fee_payment_status = 'disputed' then
    raise exception 'Pembayaran ongkir sedang diperiksa admin.';
  end if;
  if v_order.driver_fee_confirmed_at is not null then
    raise exception 'Penerimaan ongkir sudah dikonfirmasi.';
  end if;

  update public.orders
     set driver_fee_confirmed_at = pg_catalog.now(),
         delivery_fee_payment_method = p_payment_method,
         delivery_fee_payment_status = case
           when buyer_fee_confirmed_at is not null then 'confirmed'
           else 'driver_confirmed'
         end,
         delivery_fee_paid_at = case
           when buyer_fee_confirmed_at is not null then pg_catalog.now()
           else null
         end
   where id = p_order_id;
end;
$function$;

commit;
