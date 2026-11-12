do $migration$
declare
  v_name text;
  v_oid oid;
  v_def text;
  v_targets text[] := array[
    'can_upload_product_image',
    'current_user_can_read_delivery_order',
    'current_user_is_assigned_driver'
  ];
begin
  foreach v_name in array v_targets loop
    select p.oid into v_oid
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=v_name and p.prosecdef
      and has_function_privilege('authenticated',p.oid,'EXECUTE')
    limit 1;
    if v_oid is null then raise exception 'Fungsi helper tidak ditemukan: %',v_name; end if;
    v_def:=pg_get_functiondef(v_oid);
    if position('public.current_user_is_active() and exists' in v_def)=0 then
      if position('AS $function$' || E'\n  select exists (' in v_def)=0 then
        raise exception 'Pola helper tidak cocok: %',v_name;
      end if;
      v_def:=replace(v_def,'AS $function$' || E'\n  select exists (',
        'AS $function$' || E'\n  select public.current_user_is_active() and exists (');
      execute v_def;
    end if;
  end loop;
end;
$migration$;