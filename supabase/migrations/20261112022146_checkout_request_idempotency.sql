-- Pasar Hanakau: lindungi checkout dari pesanan ganda ketika respons jaringan terputus.
-- Kunci berlaku per pembeli dan mengembalikan hasil transaksi pertama untuk permintaan yang sama.
-- Tabel tidak dapat dibaca atau ditulis langsung oleh peran aplikasi.

begin;

create table if not exists public.checkout_idempotency (
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  idempotency_key uuid not null,
  request_payload jsonb not null,
  response jsonb,
  created_at timestamptz not null default pg_catalog.now(),
  primary key (buyer_id, idempotency_key),
  constraint checkout_idempotency_payload_object
    check (pg_catalog.jsonb_typeof(request_payload) = 'object'),
  constraint checkout_idempotency_response_array
    check (response is null or pg_catalog.jsonb_typeof(response) = 'array')
);

alter table public.checkout_idempotency enable row level security;
revoke all on table public.checkout_idempotency from public, anon, authenticated, service_role;

create or replace function public.checkout_cart_idempotent_secure(
  p_buyer_id uuid,
  p_idempotency_key uuid,
  p_items jsonb,
  p_delivery_address text,
  p_notes text,
  p_delivery_latitude numeric,
  p_delivery_longitude numeric,
  p_delivery_fees jsonb,
  p_voucher_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_payload jsonb;
  v_saved_payload jsonb;
  v_saved_response jsonb;
  v_inserted integer;
  v_result jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Akses checkout server tidak sah';
  end if;
  if p_buyer_id is null or p_idempotency_key is null then
    raise exception 'Identitas checkout tidak valid';
  end if;

  -- GPS can vary slightly between retries; the validated address and cart define the same intent.
  v_payload := pg_catalog.jsonb_build_object(
    'items', p_items,
    'delivery_address', coalesce(pg_catalog.btrim(p_delivery_address), ''),
    'notes', coalesce(pg_catalog.btrim(p_notes), ''),
    'voucher_code', coalesce(nullif(pg_catalog.upper(pg_catalog.btrim(coalesce(p_voucher_code, ''))), ''), '')
  );

  insert into public.checkout_idempotency
    (buyer_id, idempotency_key, request_payload)
  values
    (p_buyer_id, p_idempotency_key, v_payload)
  on conflict (buyer_id, idempotency_key) do nothing;

  get diagnostics v_inserted = row_count;

  select request_payload, response
    into v_saved_payload, v_saved_response
    from public.checkout_idempotency
   where buyer_id = p_buyer_id
     and idempotency_key = p_idempotency_key
   for update;

  if not found then
    raise exception 'Status percobaan checkout tidak dapat diverifikasi';
  end if;
  if v_saved_payload is distinct from v_payload then
    raise exception 'Kunci checkout sudah digunakan untuk keranjang atau alamat yang berbeda. Periksa riwayat pesanan terlebih dahulu.';
  end if;
  if v_saved_response is not null then
    return v_saved_response;
  end if;
  if v_inserted = 0 then
    raise exception 'Checkout dengan kunci ini masih diproses. Muat ulang riwayat pesanan sebelum mencoba lagi.';
  end if;

  v_result := public.checkout_cart_with_voucher_secure(
    p_buyer_id,
    p_items,
    p_delivery_address,
    p_notes,
    p_delivery_latitude,
    p_delivery_longitude,
    p_delivery_fees,
    p_voucher_code
  );

  update public.checkout_idempotency
     set response = v_result
   where buyer_id = p_buyer_id
     and idempotency_key = p_idempotency_key;

  return v_result;
end;
$function$;

revoke all on function public.checkout_cart_idempotent_secure(
  uuid, uuid, jsonb, text, text, numeric, numeric, jsonb, text
) from public, anon, authenticated;
grant execute on function public.checkout_cart_idempotent_secure(
  uuid, uuid, jsonb, text, text, numeric, numeric, jsonb, text
) to service_role;

commit;
