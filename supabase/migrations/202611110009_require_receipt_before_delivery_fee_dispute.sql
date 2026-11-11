-- A buyer can only dispute delivery-fee payment after confirming receipt.
create or replace function public.buyer_report_delivery_fee_dispute(p_order_id uuid, p_note text)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if length(trim(coalesce(p_note,''))) < 5 or length(trim(coalesce(p_note,''))) > 500 then
    raise exception 'Keterangan masalah harus berisi 5 sampai 500 karakter.';
  end if;

  update public.orders
     set delivery_fee_payment_status = 'disputed',
         delivery_fee_dispute_note = trim(p_note)
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
