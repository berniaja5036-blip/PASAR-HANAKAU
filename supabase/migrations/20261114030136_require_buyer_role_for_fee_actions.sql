create or replace function public.buyer_confirm_delivery_fee(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
begin
  if not (select public.current_user_has_role('buyer')) then
    raise exception 'Hanya akun pembeli aktif yang dapat mengonfirmasi pembayaran ongkir.';
  end if;

  select * into v_order from public.orders
   where id=p_order_id and buyer_id=(select auth.uid()) for update;
  if not found then raise exception 'Pesanan tidak ditemukan untuk akun buyer ini.'; end if;
  if v_order.delivery_fee <= 0 or v_order.status <> 'delivered' or v_order.buyer_received_at is null then
    raise exception 'Konfirmasi ongkir hanya tersedia setelah barang diterima pembeli.';
  end if;
  if v_order.delivery_fee_payment_status='disputed' then raise exception 'Pembayaran ongkir sedang diperiksa admin.'; end if;
  if v_order.buyer_fee_confirmed_at is not null then raise exception 'Konfirmasi buyer sudah tercatat.'; end if;
  update public.orders
     set buyer_fee_confirmed_at=pg_catalog.now(),
         delivery_fee_payment_status=case when driver_fee_confirmed_at is not null then 'confirmed' else 'buyer_confirmed' end,
         delivery_fee_paid_at=case when driver_fee_confirmed_at is not null then pg_catalog.now() else null end
   where id=p_order_id;
end;
$function$;

create or replace function public.buyer_report_delivery_fee_dispute(p_order_id uuid, p_note text)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not (select public.current_user_has_role('buyer')) then
    raise exception 'Hanya akun pembeli aktif yang dapat melaporkan sengketa ongkir.';
  end if;
  if length(pg_catalog.btrim(coalesce(p_note,''))) < 5 or length(pg_catalog.btrim(coalesce(p_note,''))) > 500 then
    raise exception 'Keterangan masalah harus berisi 5 sampai 500 karakter.';
  end if;

  update public.orders
     set delivery_fee_payment_status = 'disputed',
         delivery_fee_dispute_note = pg_catalog.btrim(p_note)
   where id = p_order_id
     and buyer_id = (select auth.uid())
     and status = 'delivered'
     and buyer_received_at is not null
     and delivery_fee > 0
     and delivery_fee_payment_status not in ('confirmed','disputed');

  if not found then
    raise exception 'Sengketa hanya dapat diajukan oleh pembeli setelah menerima barang, dan sebelum ongkir dikonfirmasi.';
  end if;
end;
$function$;

revoke all on function public.buyer_confirm_delivery_fee(uuid) from public, anon;
grant execute on function public.buyer_confirm_delivery_fee(uuid) to authenticated;
revoke all on function public.buyer_report_delivery_fee_dispute(uuid,text) from public, anon;
grant execute on function public.buyer_report_delivery_fee_dispute(uuid,text) to authenticated;
