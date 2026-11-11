-- Atomically reserve a voucher, create all shop orders, and distribute the discount.

create or replace function public.checkout_cart_with_voucher_secure(
  p_buyer_id uuid,p_items jsonb,p_delivery_address text,p_notes text,
  p_delivery_latitude numeric,p_delivery_longitude numeric,p_delivery_fees jsonb,
  p_voucher_code text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_created jsonb;
  v_voucher public.promo_vouchers%rowtype;
  v_code text := nullif(upper(trim(coalesce(p_voucher_code,''))), '');
  v_subtotal numeric(14,2);
  v_discount numeric(14,2);
  v_remaining numeric(14,2);
  v_alloc numeric(14,2);
  v_group uuid := gen_random_uuid();
  v_ids uuid[] := '{}';
  v_item record;
  v_count integer;
  v_used integer;
  v_buyer_used integer;
  v_order_id uuid;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'Akses checkout server tidak sah'; end if;
  if v_code is not null then
    select * into v_voucher from public.promo_vouchers where code=v_code for update;
    if not found then raise exception 'Kode voucher tidak ditemukan.'; end if;
    if not v_voucher.active or v_voucher.starts_at>now() or (v_voucher.ends_at is not null and v_voucher.ends_at<=now()) then raise exception 'Voucher belum berlaku atau sudah berakhir.'; end if;
    if v_voucher.discount_type='percentage' and v_voucher.discount_value>100 then raise exception 'Pengaturan persentase voucher tidak valid.'; end if;
    select count(*) into v_used from public.voucher_redemptions where voucher_id=v_voucher.id;
    if v_voucher.usage_limit is not null and v_used>=v_voucher.usage_limit then raise exception 'Kuota voucher sudah habis.'; end if;
    select count(*) into v_buyer_used from public.voucher_redemptions where voucher_id=v_voucher.id and buyer_id=p_buyer_id;
    if v_buyer_used>=v_voucher.per_buyer_limit then raise exception 'Batas penggunaan voucher untuk akun Anda sudah tercapai.'; end if;
  end if;
  v_created:=public.checkout_cart_secure(p_buyer_id,p_items,p_delivery_address,p_notes,p_delivery_latitude,p_delivery_longitude,p_delivery_fees);
  if v_code is null then return v_created; end if;
  select coalesce(sum((x->>'subtotal')::numeric),0) into v_subtotal from jsonb_array_elements(v_created) x;
  if v_subtotal<v_voucher.min_subtotal then raise exception 'Minimal belanja untuk voucher ini belum terpenuhi.'; end if;
  if v_voucher.discount_type='percentage' then v_discount:=round(v_subtotal*v_voucher.discount_value/100,2); else v_discount:=v_voucher.discount_value; end if;
  if v_voucher.max_discount is not null then v_discount:=least(v_discount,v_voucher.max_discount); end if;
  v_discount:=least(v_discount,v_subtotal);
  if v_discount<=0 then raise exception 'Nilai potongan voucher tidak valid.'; end if;
  v_remaining:=v_discount;
  select count(*) into v_count from jsonb_array_elements(v_created);
  for v_item in select value,ordinality from jsonb_array_elements(v_created) with ordinality order by ordinality loop
    v_order_id:=(v_item.value->>'order_id')::uuid;
    v_ids:=array_append(v_ids,v_order_id);
    if v_item.ordinality=v_count then v_alloc:=v_remaining;
    else v_alloc:=least(round(v_discount*(v_item.value->>'subtotal')::numeric/v_subtotal,2),v_remaining); end if;
    v_remaining:=v_remaining-v_alloc;
    update public.orders set voucher_id=v_voucher.id,discount_amount=v_alloc,checkout_group_id=v_group,total=subtotal+delivery_fee-v_alloc where id=v_order_id and buyer_id=p_buyer_id;
  end loop;
  insert into public.voucher_redemptions(voucher_id,buyer_id,checkout_group_id,discount_amount,order_ids)
  values(v_voucher.id,p_buyer_id,v_group,v_discount,v_ids);
  return (select jsonb_agg(jsonb_set(jsonb_set(value,'{discount_amount}',to_jsonb((select o.discount_amount from public.orders o where o.id=(value->>'order_id')::uuid)),'{total}',to_jsonb((select o.total from public.orders o where o.id=(value->>'order_id')::uuid))) order by ordinality from jsonb_array_elements(v_created) with ordinality);
end;
$$;
revoke all on function public.checkout_cart_with_voucher_secure(uuid,jsonb,text,text,numeric,numeric,jsonb,text) from public,anon,authenticated;
grant execute on function public.checkout_cart_with_voucher_secure(uuid,jsonb,text,text,numeric,numeric,jsonb,text) to service_role;
