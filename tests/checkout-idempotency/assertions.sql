\set ON_ERROR_STOP on

insert into public.profiles(id) values
  ('10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000002');

do $test$
declare
  v_buyer uuid := '10000000-0000-4000-8000-000000000001';
  v_other_buyer uuid := '10000000-0000-4000-8000-000000000002';
  v_key uuid := '20000000-0000-4000-8000-000000000001';
  v_pending_key uuid := '20000000-0000-4000-8000-000000000002';
  v_items jsonb := '[{"product_id":"30000000-0000-4000-8000-000000000001","quantity":2}]'::jsonb;
  v_fees jsonb := '[]'::jsonb;
  v_first jsonb;
  v_replay jsonb;
  v_other jsonb;
  v_preflight jsonb;
  v_error text;
begin
  if pg_catalog.has_table_privilege('anon', 'public.checkout_idempotency', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'public.checkout_idempotency', 'SELECT')
     or pg_catalog.has_table_privilege('service_role', 'public.checkout_idempotency', 'SELECT') then
    raise exception 'Checkout idempotency records must not be directly readable by client or service roles.';
  end if;

  if pg_catalog.has_function_privilege(
       'anon',
       'public.checkout_cart_idempotent_secure(uuid,uuid,jsonb,text,text,numeric,numeric,jsonb,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public.checkout_cart_idempotent_secure(uuid,uuid,jsonb,text,text,numeric,numeric,jsonb,text)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'public.checkout_cart_idempotent_secure(uuid,uuid,jsonb,text,text,numeric,numeric,jsonb,text)',
       'EXECUTE'
     ) then
    raise exception 'Idempotent checkout must be executable only by service_role.';
  end if;

  if pg_catalog.has_function_privilege(
       'anon',
       'public.get_checkout_idempotent_result_secure(uuid,uuid,jsonb,text,text,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public.get_checkout_idempotent_result_secure(uuid,uuid,jsonb,text,text,text)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'public.get_checkout_idempotent_result_secure(uuid,uuid,jsonb,text,text,text)',
       'EXECUTE'
     ) then
    raise exception 'Checkout retry preflight must be executable only by service_role.';
  end if;

  -- Even a direct invocation under an authenticated JWT claim must fail closed.
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', false);
  v_error := null;
  begin
    perform public.checkout_cart_idempotent_secure(
      v_buyer, v_key, v_items, 'Jalan Hanakau', 'depan balai',
      -4.8, 104.8, v_fees, 'PROMO'
    );
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is null or v_error not like '%Akses checkout server tidak sah%' then
    raise exception 'Authenticated role was not rejected by checkout RPC.';
  end if;

  perform pg_catalog.set_config('request.jwt.claim.role', 'service_role', false);

  -- A successful first request is saved. A retry with normalized-equivalent
  -- address, notes, and voucher input returns the original result.
  v_first := public.checkout_cart_idempotent_secure(
    v_buyer, v_key, v_items, '  Jalan Hanakau  ', '  depan balai  ',
    -4.8, 104.8, v_fees, ' promo '
  );
  v_replay := public.checkout_cart_idempotent_secure(
    v_buyer, v_key, v_items, 'Jalan Hanakau', 'depan balai',
    -4.8, 104.8, v_fees, 'PROMO'
  );
  if v_first is distinct from v_replay then
    raise exception 'A repeated checkout did not return the original response.';
  end if;
  if (select call_count from public.checkout_test_calls) <> 1 then
    raise exception 'A repeated checkout invoked the order-creation transaction more than once.';
  end if;

  -- Reusing a key for a different cart/address must fail without creating
  -- another order or overwriting the original request.
  v_error := null;
  begin
    perform public.checkout_cart_idempotent_secure(
      v_buyer, v_key,
      '[{"product_id":"30000000-0000-4000-8000-000000000001","quantity":3}]'::jsonb,
      'Jalan Hanakau', 'depan balai', -4.8, 104.8, v_fees, 'PROMO'
    );
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is null or v_error not like '%Kunci checkout sudah digunakan%' then
    raise exception 'Reusing a key with a different payload was not rejected.';
  end if;
  if (select call_count from public.checkout_test_calls) <> 1 then
    raise exception 'A mismatched retry unexpectedly invoked order creation.';
  end if;

  -- Keys are scoped by buyer, so another account may safely use the same UUID.
  v_other := public.checkout_cart_idempotent_secure(
    v_other_buyer, v_key, v_items, 'Jalan Hanakau', 'depan balai',
    -4.8, 104.8, v_fees, 'PROMO'
  );
  if v_other = v_first then
    raise exception 'Idempotency records were not scoped to the buyer.';
  end if;
  if (select call_count from public.checkout_test_calls) <> 2 then
    raise exception 'A different buyer did not receive an independent checkout attempt.';
  end if;

  -- A request left without a response is explicitly reported as in progress;
  -- it must not execute order creation a second time.
  insert into public.checkout_idempotency(buyer_id, idempotency_key, request_payload)
  values (
    v_buyer,
    v_pending_key,
    pg_catalog.jsonb_build_object(
      'items', v_items,
      'delivery_address', 'Jalan Hanakau',
      'notes', 'depan balai',
      'voucher_code', 'PROMO'
    )
  );

  v_preflight := public.get_checkout_idempotent_result_secure(
    v_buyer, v_pending_key, v_items,
    '  Jalan Hanakau ', ' depan balai ', ' promo '
  );
  if v_preflight is distinct from pg_catalog.jsonb_build_object('_checkout_in_progress', true) then
    raise exception 'An unfinished checkout was not reported as in progress.';
  end if;

  v_error := null;
  begin
    perform public.checkout_cart_idempotent_secure(
      v_buyer, v_pending_key, v_items,
      'Jalan Hanakau', 'depan balai', -4.8, 104.8, v_fees, 'PROMO'
    );
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is null or v_error not like '%masih diproses%' then
    raise exception 'An unfinished checkout was allowed to create a duplicate order.';
  end if;
  if (select call_count from public.checkout_test_calls) <> 2 then
    raise exception 'An in-progress retry invoked order creation.';
  end if;

  v_preflight := public.get_checkout_idempotent_result_secure(
    v_buyer, '20000000-0000-4000-8000-000000000099',
    v_items, 'Jalan Hanakau', 'depan balai', 'PROMO'
  );
  if v_preflight is not null then
    raise exception 'Unknown checkout key should return null from retry preflight.';
  end if;
end;
$test$;

select 'Checkout idempotency, replay, payload binding, in-progress handling, and role grants passed.' as result;
