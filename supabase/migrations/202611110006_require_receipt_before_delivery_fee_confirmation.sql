create or replace function public.buyer_confirm_delivery_fee(p_order_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_order public.orders%rowtype;
begin
  select * into v_order from public.orders where id=p_order_id and buyer_id=(select auth.uid()) for update;
  if not found then raise exception 'Pesanan tidak ditemukan untuk akun buyer ini.'; end if;
  if v_order.delivery_fee<=0 or v_order.status<>'delivered' or v_order.buyer_received_at is null then raise exception 'Konfirmasi ongkir hanya tersedia setelah barang diterima pembeli.'; end if;
  if v_order.delivery_fee_payment_status='disputed' then raise exception 'Pembayaran ongkir sedang diperiksa admin.'; end if;
  if v_order.buyer_fee_confirmed_at is not null then raise exception 'Konfirmasi buyer sudah tercatat.'; end if;
  update public.orders set buyer_fee_confirmed_at=now(),delivery_fee_payment_status=case when driver_fee_confirmed_at is not null then 'confirmed' else 'buyer_confirmed' end,delivery_fee_paid_at=case when driver_fee_confirmed_at is not null then now() else null end where id=p_order_id;
end;
$$;

create or replace function public.driver_confirm_delivery_fee(p_order_id uuid,p_payment_method text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_order public.orders%rowtype;
begin
  if p_payment_method is null or p_payment_method not in ('cash','transfer') then raise exception 'Metode pembayaran ongkir harus tunai atau transfer.'; end if;
  select o.* into v_order from public.orders o join public.deliveries d on d.order_id=o.id where o.id=p_order_id and d.driver_id=(select auth.uid()) for update of o;
  if not found then raise exception 'Pesanan tidak ditemukan untuk driver ini.'; end if;
  if v_order.status<>'delivered' or v_order.delivery_fee<=0 or v_order.buyer_received_at is null then raise exception 'Konfirmasi ongkir hanya tersedia setelah barang diterima pembeli dan ongkir lebih dari nol.'; end if;
  if v_order.delivery_fee_payment_status='disputed' then raise exception 'Pembayaran ongkir sedang diperiksa admin.'; end if;
  if v_order.driver_fee_confirmed_at is not null then raise exception 'Penerimaan ongkir sudah dikonfirmasi.'; end if;
  update public.orders set driver_fee_confirmed_at=now(),delivery_fee_payment_method=p_payment_method,delivery_fee_payment_status=case when buyer_fee_confirmed_at is not null then 'confirmed' else 'driver_confirmed' end,delivery_fee_paid_at=case when buyer_fee_confirmed_at is not null then now() else null end where id=p_order_id;
end;
$$;