-- Secure server-side checkout. The browser cannot execute this RPC;
-- only the checkout Edge Function's service role may call it.
begin;

CREATE OR REPLACE FUNCTION public.checkout_cart_secure(p_buyer_id uuid, p_items jsonb, p_delivery_address text, p_notes text, p_delivery_latitude numeric, p_delivery_longitude numeric, p_delivery_fees jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_item_count integer;
  v_shop record;
  v_order_id uuid;
  v_order_number text;
  v_subtotal numeric(14,2);
  v_fee numeric(14,2);
  v_distance integer;
  v_enabled boolean;
  v_result jsonb := '[]'::jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'Akses checkout server tidak sah';
  end if;
  if p_buyer_id is null or not exists (
    select 1 from public.profiles where id=p_buyer_id and role='buyer' and account_status='active'
  ) then
    raise exception 'Akun pembeli tidak valid';
  end if;
  if p_items is null or jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'Daftar belanja tidak valid';
  end if;
  v_item_count := jsonb_array_length(p_items);
  if v_item_count < 1 or v_item_count > 30 then
    raise exception 'Keranjang harus berisi 1 sampai 30 jenis produk';
  end if;
  if coalesce(length(trim(p_delivery_address)),0) < 8 then
    raise exception 'Alamat pengantaran harus diisi dengan lengkap';
  end if;
  if p_delivery_latitude is null or p_delivery_longitude is null
     or p_delivery_latitude not between -90 and 90
     or p_delivery_longitude not between -180 and 180 then
    raise exception 'Koordinat pengantaran tidak valid';
  end if;
  if jsonb_typeof(p_delivery_fees) is distinct from 'array' then
    raise exception 'Rincian ongkir server tidak valid';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) e
    where coalesce(e.value->>'product_id','') = ''
       or coalesce((e.value->>'quantity')::integer,0) < 1
       or (e.value->>'quantity')::integer > 100
  ) then
    raise exception 'Produk atau jumlah barang tidak valid';
  end if;
  if (select count(distinct (e.value->>'product_id')::uuid)
      from jsonb_array_elements(p_items) e) <> v_item_count then
    raise exception 'Produk yang sama tidak boleh dicantumkan berulang';
  end if;

  perform p.id
  from public.products p
  join jsonb_array_elements(p_items) e on p.id=(e.value->>'product_id')::uuid
  order by p.id for update of p;

  if (select count(*) from jsonb_array_elements(p_items) e
      join public.products p on p.id=(e.value->>'product_id')::uuid) <> v_item_count then
    raise exception 'Ada produk yang sudah tidak tersedia';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) e
    join public.products p on p.id=(e.value->>'product_id')::uuid
    join public.shops s on s.id=p.shop_id
    where p.status <> 'active' or s.status <> 'approved'
       or p.stock < (e.value->>'quantity')::integer
  ) then
    raise exception 'Stok produk tidak cukup atau produk tidak lagi tersedia';
  end if;

  select enabled into v_enabled from public.delivery_fee_settings where id=true;
  if v_enabled is null then raise exception 'Pengaturan ongkir belum tersedia'; end if;

  if (select count(distinct (f.value->>'shop_id')::uuid)
      from jsonb_array_elements(p_delivery_fees) f)
     <> (select count(distinct p.shop_id)
         from jsonb_array_elements(p_items) e
         join public.products p on p.id=(e.value->>'product_id')::uuid) then
    raise exception 'Rincian ongkir tidak sesuai dengan jumlah toko';
  end if;

  for v_shop in
    select distinct s.id,s.name,s.pickup_latitude,s.pickup_longitude
    from jsonb_array_elements(p_items) e
    join public.products p on p.id=(e.value->>'product_id')::uuid
    join public.shops s on s.id=p.shop_id
    order by s.id
  loop
    if v_shop.pickup_latitude is null or v_shop.pickup_longitude is null then
      raise exception 'Toko % belum menyimpan titik penjemputan',v_shop.name;
    end if;

    select coalesce((f.value->>'delivery_fee')::numeric,-1),
           coalesce((f.value->>'distance_meters')::integer,-1)
      into v_fee,v_distance
    from jsonb_array_elements(p_delivery_fees) f
    where (f.value->>'shop_id')::uuid=v_shop.id;

    if v_fee < 0 or v_distance <= 0 then
      raise exception 'Data ongkir untuk toko % tidak valid',v_shop.name;
    end if;
    if not v_enabled and v_fee <> 0 then
      raise exception 'Ongkir masih nonaktif; biaya harus nol';
    end if;
    if v_enabled and (
      ceil(v_distance::numeric/1000) > (select max_distance_km from public.delivery_fee_settings where id=true)
      or v_fee <> greatest(
        (select minimum_fee from public.delivery_fee_settings where id=true),
        (select base_fee from public.delivery_fee_settings where id=true)
          + ceil(v_distance::numeric/1000) * (select per_km_fee from public.delivery_fee_settings where id=true)
      )
    ) then
      raise exception 'Nominal ongkir tidak sesuai tarif yang berlaku';
    end if;

    select coalesce(sum(p.price*(e.value->>'quantity')::integer),0)
      into v_subtotal
    from jsonb_array_elements(p_items) e
    join public.products p on p.id=(e.value->>'product_id')::uuid
    where p.shop_id=v_shop.id;

    v_order_number := 'PH-'||to_char(now(),'YYMMDD')||'-'||
      upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));

    insert into public.orders
      (order_number,buyer_id,status,subtotal,delivery_fee,total,delivery_address,notes,
       pickup_latitude,pickup_longitude,delivery_latitude,delivery_longitude,
       route_distance_m,delivery_fee_payment_status)
    values
      (v_order_number,p_buyer_id,'pending',v_subtotal,v_fee,v_subtotal+v_fee,
       trim(p_delivery_address),coalesce(trim(p_notes),''),
       v_shop.pickup_latitude,v_shop.pickup_longitude,p_delivery_latitude,p_delivery_longitude,
       v_distance,'unpaid')
    returning id into v_order_id;

    insert into public.order_items
      (order_id,product_id,shop_id,product_name,unit_price,quantity,line_total)
    select v_order_id,p.id,p.shop_id,p.name,p.price,
           (e.value->>'quantity')::integer,p.price*(e.value->>'quantity')::integer
    from jsonb_array_elements(p_items) e
    join public.products p on p.id=(e.value->>'product_id')::uuid
    where p.shop_id=v_shop.id;

    update public.products p
    set stock=p.stock-(e.value->>'quantity')::integer
    from jsonb_array_elements(p_items) e
    where p.id=(e.value->>'product_id')::uuid and p.shop_id=v_shop.id;

    insert into public.deliveries(order_id,status) values(v_order_id,'waiting');

    v_result := v_result || jsonb_build_array(jsonb_build_object(
      'order_id',v_order_id,'order_number',v_order_number,
      'shop_name',v_shop.name,'subtotal',v_subtotal,
      'delivery_fee',v_fee,'total',v_subtotal+v_fee,
      'route_distance_m',v_distance,'status','pending'
    ));
  end loop;
  return v_result;
end;
$function$


revoke all on function public.checkout_cart_secure(uuid,jsonb,text,text,numeric,numeric,jsonb) from public, anon, authenticated;
grant execute on function public.checkout_cart_secure(uuid,jsonb,text,text,numeric,numeric,jsonb) to service_role;

commit;
