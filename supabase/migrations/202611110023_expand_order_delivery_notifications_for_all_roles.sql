-- Send order and delivery status events to the relevant buyer, seller, admin and driver accounts.
create or replace function public.notify_order_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_title text;
  v_body text;
  v_key text;
  v_shop record;
begin
  if tg_op = 'INSERT' then
    v_title := 'Pesanan baru dibuat';
    v_body := 'Pesanan ' || new.order_number || ' berhasil dibuat.';
    v_key := new.id::text || ':order-created';
    insert into public.notifications(user_id,title,body,target_path,event_key)
    values(new.buyer_id,v_title,v_body,'./#orders',v_key)
    on conflict(user_id,event_key) do nothing;
    insert into public.notifications(user_id,title,body,target_path,event_key)
    select p.id,'Pesanan baru','Pesanan baru masuk: ' || new.order_number || '.','./#admin-orders',v_key
    from public.profiles p where p.role='admin'
    on conflict(user_id,event_key) do nothing;
  elsif old.status is distinct from new.status then
    v_title := case new.status
      when 'confirmed' then 'Pesanan dikonfirmasi'
      when 'ready_for_pickup' then 'Pesanan siap dijemput'
      when 'picked_up' then 'Pesanan sedang diantar'
      when 'delivered' then 'Pesanan selesai diantar'
      when 'cancelled' then 'Pesanan dibatalkan'
      else 'Status pesanan berubah' end;
    v_body := 'Status pesanan ' || new.order_number || ' sekarang: ' || new.status || '.';
    v_key := new.id::text || ':order-status:' || new.status;
    insert into public.notifications(user_id,title,body,target_path,event_key)
    values(new.buyer_id,v_title,v_body,'./#orders',v_key)
    on conflict(user_id,event_key) do nothing;
    for v_shop in
      select distinct s.owner_id from public.order_items oi
      join public.shops s on s.id=oi.shop_id where oi.order_id=new.id
    loop
      insert into public.notifications(user_id,title,body,target_path,event_key)
      values(v_shop.owner_id,v_title,v_body,'./#seller-orders',v_key)
      on conflict(user_id,event_key) do nothing;
    end loop;
    insert into public.notifications(user_id,title,body,target_path,event_key)
    select p.id,v_title,'Pesanan ' || new.order_number || ' diperbarui: ' || new.status || '.','./#admin-orders',v_key
    from public.profiles p where p.role='admin'
    on conflict(user_id,event_key) do nothing;
  end if;
  return new;
end
$function$;

create or replace function public.notify_delivery_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
  v_shop record;
  v_title text;
  v_body text;
  v_key text;
begin
  select * into v_order from public.orders where id=new.order_id;
  if not found then return new; end if;
  if new.driver_id is not null and
     (tg_op='INSERT' or old.driver_id is distinct from new.driver_id) then
    v_key := v_order.id::text || ':driver-assigned:' || new.driver_id::text;
    insert into public.notifications(user_id,title,body,target_path,event_key)
    values(new.driver_id,'Tugas penjemputan baru','Anda mendapat tugas untuk pesanan ' || v_order.order_number || '.','./#driver-tasks',v_key)
    on conflict(user_id,event_key) do nothing;
    insert into public.notifications(user_id,title,body,target_path,event_key)
    values(v_order.buyer_id,'Driver ditugaskan','Driver telah ditugaskan untuk pesanan ' || v_order.order_number || '.','./#orders',v_order.id::text || ':driver-assigned-buyer')
    on conflict(user_id,event_key) do nothing;
    for v_shop in
      select distinct s.owner_id from public.order_items oi
      join public.shops s on s.id=oi.shop_id where oi.order_id=new.order_id
    loop
      insert into public.notifications(user_id,title,body,target_path,event_key)
      values(v_shop.owner_id,'Driver ditugaskan','Driver telah ditugaskan untuk menjemput pesanan ' || v_order.order_number || '.','./#seller-orders',v_order.id::text || ':driver-assigned-seller:' || v_shop.owner_id::text)
      on conflict(user_id,event_key) do nothing;
    end loop;
    insert into public.notifications(user_id,title,body,target_path,event_key)
    select p.id,'Driver ditugaskan','Driver telah ditugaskan untuk pesanan ' || v_order.order_number || '.','./#admin-orders',v_order.id::text || ':driver-assigned-admin:' || p.id::text
    from public.profiles p where p.role='admin'
    on conflict(user_id,event_key) do nothing;
  end if;
  if tg_op='UPDATE' and old.status is distinct from new.status then
    v_title := case new.status
      when 'assigned' then 'Driver siap menjemput'
      when 'picked_up' then 'Barang sudah dijemput'
      when 'delivered' then 'Barang sudah diantar'
      when 'failed' then 'Pengiriman terkendala'
      else 'Pembaruan pengiriman' end;
    v_body := 'Pengiriman pesanan ' || v_order.order_number || ': ' || new.status || '.';
    v_key := v_order.id::text || ':delivery-status:' || new.status;
    insert into public.notifications(user_id,title,body,target_path,event_key)
    values(v_order.buyer_id,v_title,v_body,'./#orders',v_key)
    on conflict(user_id,event_key) do nothing;
    for v_shop in
      select distinct s.owner_id from public.order_items oi
      join public.shops s on s.id=oi.shop_id where oi.order_id=new.order_id
    loop
      insert into public.notifications(user_id,title,body,target_path,event_key)
      values(v_shop.owner_id,v_title,v_body,'./#seller-orders',v_key)
      on conflict(user_id,event_key) do nothing;
    end loop;
    insert into public.notifications(user_id,title,body,target_path,event_key)
    select p.id,v_title,'Pengiriman pesanan ' || v_order.order_number || ' diperbarui: ' || new.status || '.','./#admin-orders',v_key
    from public.profiles p where p.role='admin'
    on conflict(user_id,event_key) do nothing;
  end if;
  return new;
end
$function$;
revoke all on function public.notify_order_events() from public, anon, authenticated;
revoke all on function public.notify_delivery_events() from public, anon, authenticated;
