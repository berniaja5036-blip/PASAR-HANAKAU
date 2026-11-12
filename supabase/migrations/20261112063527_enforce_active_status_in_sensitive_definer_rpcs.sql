do $migration$
declare
  v_name text;
  v_oid oid;
  v_def text;
  v_guard text := E'\nbegin\n  if not public.current_user_is_active() then\n    raise exception ''Akun tidak aktif.'';\n  end if;\n';
  v_targets text[] := array[
    'buyer_confirm_delivery_fee',
    'buyer_confirm_order_received',
    'buyer_report_delivery_fee_dispute',
    'buyer_request_order_cancellation',
    'driver_confirm_delivery_fee',
    'driver_update_delivery_status'
  ];
begin
  foreach v_name in array v_targets loop
    select p.oid into v_oid
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=v_name
      and p.prosecdef and has_function_privilege('authenticated',p.oid,'EXECUTE')
    limit 1;
    if v_oid is null then raise exception 'Fungsi target tidak ditemukan: %',v_name; end if;
    v_def := pg_get_functiondef(v_oid);
    if position('public.current_user_is_active()' in v_def)=0 then
      if position(E'\nbegin\n' in v_def)=0 then
        raise exception 'Pola BEGIN tidak cocok: %',v_name;
      end if;
      v_def := replace(v_def, E'\nbegin\n', v_guard);
      execute v_def;
    end if;
  end loop;

  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='checkout_cart_secure'
    and pg_get_function_identity_arguments(p.oid) =
      'p_buyer_id uuid, p_items jsonb, p_delivery_address text, p_notes text, p_delivery_latitude numeric, p_delivery_longitude numeric, p_delivery_fees jsonb';
  if v_oid is null then raise exception 'checkout_cart_secure tidak ditemukan'; end if;
  v_def := pg_get_functiondef(v_oid);
  if position('account_status' in v_def)=0 then
    if position('where id=p_buyer_id and role=''buyer''' in v_def)=0 then
      raise exception 'Validasi pembeli checkout tidak cocok';
    end if;
    v_def := replace(v_def,
      'where id=p_buyer_id and role=''buyer''',
      'where id=p_buyer_id and role=''buyer'' and account_status=''active''');
    execute v_def;
  end if;
end;
$migration$;