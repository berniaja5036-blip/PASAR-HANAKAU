create or replace function public.get_checkout_idempotent_result_secure(
  p_buyer_id uuid, p_idempotency_key uuid, p_items jsonb,
  p_delivery_address text, p_notes text, p_voucher_code text default null
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare v_payload jsonb; v_saved_payload jsonb; v_saved_response jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'Akses checkout server tidak sah'; end if;
  v_payload := pg_catalog.jsonb_build_object(
    'items', p_items,
    'delivery_address', coalesce(pg_catalog.btrim(p_delivery_address), ''),
    'notes', coalesce(pg_catalog.btrim(p_notes), ''),
    'voucher_code', coalesce(nullif(pg_catalog.upper(pg_catalog.btrim(coalesce(p_voucher_code, ''))), ''), '')
  );
  select request_payload, response into v_saved_payload, v_saved_response
  from public.checkout_idempotency where buyer_id=p_buyer_id and idempotency_key=p_idempotency_key;
  if not found then return null; end if;
  if v_saved_payload is distinct from v_payload then
    raise exception 'Kunci checkout sudah digunakan untuk keranjang atau alamat yang berbeda. Periksa riwayat pesanan terlebih dahulu.';
  end if;
  return v_saved_response;
end;
$function$;
revoke all on function public.get_checkout_idempotent_result_secure(uuid,uuid,jsonb,text,text,text) from public, anon, authenticated;
grant execute on function public.get_checkout_idempotent_result_secure(uuid,uuid,jsonb,text,text,text) to service_role;
