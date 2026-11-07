-- Pasar Hanakau: checkout aman melalui transaksi database.
-- Berlaku untuk skema aktif aplikasi (shops/products/orders/order_items/deliveries).
-- Satu pesanan dibuat per toko agar setiap pengiriman memiliki satu titik penjemputan.
create or replace function public.checkout_cart(
  p_items jsonb,
  p_delivery_address text,
  p_notes text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_buyer uuid := (select auth.uid());
  v_item_count integer;
  v_shop record;
  v_item record;
  v_order_id uuid;
  v_order_number text;
  v_subtotal numeric(14,2);
  v_result jsonb := '[]'::jsonb;
begin
  if v_buyer is null then
    raise exception 'Silakan masuk sebelum membuat pesanan';
  end if;
  if not public.current_user_has_role('buyer') then
    raise exception 'Checkout hanya tersedia untuk akun pembeli';
  end if;
  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'Daftar belanja tidak valid';
  end if;
  v_item_count := jsonb_array_length(p_items);
  if v_item_count < 1 or v_item_count > 30 then
    raise exception 'Keranjang harus berisi 1 sampai 30 jenis produk';
  end if;
  if coalesce(length(trim(p_delivery_address)),0) < 8 then
    raise exception 'Alamat pengantaran harus diisi dengan lengkap';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) e
    where coalesce(e.value->>'product_id','') = ''
       or coalesce((e.value->>'quantity')::integer,0) < 1
       or (e.value->>'quantity')::integer > 100
  ) then
    raise exception 'Produk atau jumlah barang tidak valid';
  end if;

  if (
    select count(distinct (e.value->>'product_id')::uuid)
    from jsonb_array_elements(p_items) e
  ) <> v_item_count then
    raise exception 'Produk yang sama tidak boleh dicantumkan berulang';
  end if;

  -- Kunci semua baris produk agar stok tidak dapat dibeli bersamaan melebihi persediaan.
  perform p.id
  from public.products p
  join jsonb_array_elements(p_items) e
    on p.id = (e.value->>'product_id')::uuid
  order by p.id
  for update of p;

  if (
    select count(*)
    from jsonb_array_elements(p_items) e
    join public.products p on p.id = (e.value->>'product_id')::uuid
  ) <> v_item_count then
    raise exception 'Ada produk yang sudah tidak tersedia';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) e
    join public.products p on p.id = (e.value->>'product_id')::uuid
    join public.shops s on s.id = p.shop_id
    where p.status <> 'active'
       or s.status <> 'approved'
       or p.stock < (e.value->>'quantity')::integer
  ) then
    raise exception 'Stok produk tidak cukup atau produk tidak lagi tersedia';
  end if;

  -- Pisahkan pesanan per toko agar setiap kurir memiliki satu lokasi penjemputan.
  for v_shop in
    select distinct s.id, s.name, s.address
    from jsonb_array_elements(p_items) e
    join public.products p on p.id = (e.value->>'product_id')::uuid
    join public.shops s on s.id = p.shop_id
    order by s.id
  loop
    select coalesce(sum(p.price * (e.value->>'quantity')::integer),0)
      into v_subtotal
    from jsonb_array_elements(p_items) e
    join public.products p on p.id = (e.value->>'product_id')::uuid
    where p.shop_id = v_shop.id;

    v_order_number := 'PH-' || to_char(now(),'YYMMDD') || '-' ||
      upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));

    insert into public.orders
      (order_number,buyer_id,status,subtotal,delivery_fee,total,delivery_address,notes)
    values
      (v_order_number,v_buyer,'pending',v_subtotal,0,v_subtotal,
       trim(p_delivery_address),coalesce(trim(p_notes),'' ))
    returning id into v_order_id;

    insert into public.order_items
      (order_id,product_id,shop_id,product_name,unit_price,quantity,line_total)
    select v_order_id,p.id,p.shop_id,p.name,p.price,
           (e.value->>'quantity')::integer,
           p.price * (e.value->>'quantity')::integer
    from jsonb_array_elements(p_items) e
    join public.products p on p.id = (e.value->>'product_id')::uuid
    where p.shop_id = v_shop.id;

    update public.products p
    set stock = p.stock - (e.value->>'quantity')::integer
    from jsonb_array_elements(p_items) e
    where p.id = (e.value->>'product_id')::uuid
      and p.shop_id = v_shop.id;

    insert into public.deliveries (order_id,status)
    values (v_order_id,'waiting');

    v_result := v_result || jsonb_build_array(jsonb_build_object(
      'order_id',v_order_id,
      'order_number',v_order_number,
      'shop_name',v_shop.name,
      'subtotal',v_subtotal,
      'status','pending'
    ));
  end loop;

  return v_result;
end;
$$;

revoke all on function public.checkout_cart(jsonb,text,text) from public;
grant execute on function public.checkout_cart(jsonb,text,text) to authenticated;
