create or replace function public.notify_order_item_seller()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_order public.orders%rowtype; v_owner uuid;
begin
 select * into v_order from public.orders where id=new.order_id;
 select owner_id into v_owner from public.shops where id=new.shop_id;
 if v_order.id is not null and v_owner is not null then
  insert into public.notifications(user_id,title,body,target_path,event_key)
  values(v_owner,'Pesanan masuk','Ada pesanan baru: '||v_order.order_number||'.','./#seller-orders',v_order.id::text||':order-created')
  on conflict(user_id,event_key) do nothing;
 end if;
 return new;
end $$;
drop trigger if exists trg_notify_order_item_seller on public.order_items;
create trigger trg_notify_order_item_seller after insert on public.order_items for each row execute function public.notify_order_item_seller();
revoke execute on function public.notify_order_item_seller() from public,anon,authenticated;

create or replace function public.notify_delivery_events()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_order public.orders%rowtype; v_shop record; v_title text; v_body text; v_key text;
begin
 select * into v_order from public.orders where id=new.order_id; if not found then return new; end if;
 if new.driver_id is not null and (tg_op='INSERT' or old.driver_id is distinct from new.driver_id) then
  v_key := v_order.id::text||':driver-assigned:'||new.driver_id::text;
  insert into public.notifications(user_id,title,body,target_path,event_key)
  values(new.driver_id,'Tugas penjemputan baru','Anda mendapat tugas untuk pesanan '||v_order.order_number||'.','./#driver-tasks',v_key)
  on conflict(user_id,event_key) do nothing;
  insert into public.notifications(user_id,title,body,target_path,event_key)
  values(v_order.buyer_id,'Driver ditugaskan','Driver telah ditugaskan untuk pesanan '||v_order.order_number||'.','./#orders',v_order.id::text||':driver-assigned-buyer')
  on conflict(user_id,event_key) do nothing;
 end if;
 if tg_op='UPDATE' and old.status is distinct from new.status then
  v_title := case new.status when 'assigned' then 'Driver siap menjemput' when 'picked_up' then 'Barang sudah dijemput' when 'delivered' then 'Barang sudah diantar' when 'failed' then 'Pengiriman terkendala' else 'Pembaruan pengiriman' end;
  v_body := 'Pengiriman pesanan '||v_order.order_number||': '||new.status||'.'; v_key := v_order.id::text||':delivery-status:'||new.status;
  for v_shop in select distinct s.owner_id from public.order_items oi join public.shops s on s.id=oi.shop_id where oi.order_id=new.order_id loop
   insert into public.notifications(user_id,title,body,target_path,event_key)
   values(v_shop.owner_id,v_title,v_body,'./#seller-orders',v_key)
   on conflict(user_id,event_key) do nothing;
  end loop;
 end if;
 return new;
end $$;
