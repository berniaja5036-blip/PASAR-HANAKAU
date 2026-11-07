-- Pasar Hanakau: pembatalan hanya sebelum admin mengonfirmasi pesanan.
-- Jalankan sekali di Supabase SQL Editor setelah migrasi 015.

update public.order_cancellation_requests r
   set status='rejected',
       admin_note='Permintaan ditutup karena pesanan sudah dikonfirmasi atau masuk tahap pengiriman.',
       reviewed_at=now()
  from public.orders o
 where o.id=r.order_id and r.status='pending' and o.status<>'pending';

create or replace function public.buyer_request_order_cancellation(p_order_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_order public.orders%rowtype; v_request_id uuid;
begin
 if (select auth.uid()) is null then raise exception 'Silakan masuk terlebih dahulu.'; end if;
 if length(trim(coalesce(p_reason,'')))<5 or length(trim(coalesce(p_reason,'')))>500 then raise exception 'Alasan pembatalan harus berisi 5 sampai 500 karakter.'; end if;
 select * into v_order from public.orders where id=p_order_id and buyer_id=(select auth.uid()) for update;
 if not found then raise exception 'Pesanan tidak ditemukan untuk akun pembeli ini.'; end if;
 if v_order.status<>'pending' then raise exception 'Pembatalan hanya dapat diajukan sebelum admin mengonfirmasi pesanan.'; end if;
 insert into public.order_cancellation_requests(order_id,buyer_id,reason) values(p_order_id,(select auth.uid()),trim(p_reason)) returning id into v_request_id;
 return v_request_id;
exception when unique_violation then raise exception 'Masih ada permintaan pembatalan yang menunggu pemeriksaan admin.';
end;
$$;
revoke all on function public.buyer_request_order_cancellation(uuid,text) from public,anon;
grant execute on function public.buyer_request_order_cancellation(uuid,text) to authenticated;

create or replace function public.admin_update_order_status(p_order_id uuid,p_new_status text)
returns void language plpgsql security definer set search_path=''
as $$
declare v_current_status text; v_allowed boolean:=false;
begin
 if not coalesce(public.is_admin(),false) then raise exception 'Hanya admin yang dapat mengubah status pesanan.'; end if;
 if p_new_status not in ('confirmed','ready_for_pickup','cancelled') then raise exception 'Status pesanan tidak valid untuk admin.'; end if;
 select o.status into v_current_status from public.orders o where o.id=p_order_id for update;
 if not found then raise exception 'Pesanan tidak ditemukan.'; end if;
 if v_current_status='pending' and p_new_status='confirmed' and exists(select 1 from public.order_cancellation_requests r where r.order_id=p_order_id and r.status='pending') then
  raise exception 'Pesanan memiliki permintaan pembatalan. Setujui atau tolak permintaan tersebut terlebih dahulu.';
 end if;
 v_allowed:=(v_current_status='pending' and p_new_status in ('confirmed','cancelled')) or (v_current_status='confirmed' and p_new_status in ('ready_for_pickup','cancelled'));
 if not v_allowed then raise exception 'Perubahan status dari % ke % tidak diizinkan.',v_current_status,p_new_status; end if;
 update public.orders set status=p_new_status where id=p_order_id;
end;
$$;
revoke all on function public.admin_update_order_status(uuid,text) from public,anon;
grant execute on function public.admin_update_order_status(uuid,text) to authenticated;

create or replace function public.admin_review_order_cancellation(p_request_id uuid,p_approve boolean,p_admin_note text default '')
returns void language plpgsql security definer set search_path=''
as $$
declare v_request public.order_cancellation_requests%rowtype; v_order public.orders%rowtype;
begin
 if not coalesce(public.is_admin(),false) then raise exception 'Hanya admin yang dapat memproses pembatalan.'; end if;
 select * into v_request from public.order_cancellation_requests where id=p_request_id for update;
 if not found then raise exception 'Permintaan pembatalan tidak ditemukan.'; end if;
 if v_request.status<>'pending' then raise exception 'Permintaan ini sudah diproses.'; end if;
 select * into v_order from public.orders where id=v_request.order_id for update;
 if not found then raise exception 'Pesanan tidak ditemukan.'; end if;
 if v_order.status<>'pending' then raise exception 'Pesanan sudah dikonfirmasi admin; permintaan pembatalan tidak dapat diproses.'; end if;
 if p_approve then
  update public.products p set stock=p.stock+item_totals.quantity
   from (select product_id,sum(quantity)::integer as quantity from public.order_items where order_id=v_order.id and product_id is not null group by product_id) item_totals
   where p.id=item_totals.product_id;
  update public.orders set status='cancelled' where id=v_order.id;
  update public.deliveries set status='failed',delivery_notes='Pesanan dibatalkan setelah persetujuan admin.' where order_id=v_order.id and status='waiting';
 end if;
 update public.order_cancellation_requests set status=case when p_approve then 'approved' else 'rejected' end,
  admin_note=nullif(trim(coalesce(p_admin_note,'')),''),
  reviewed_by=(select auth.uid()),reviewed_at=now()
 where id=v_request.id;
end;
$$;
revoke all on function public.admin_review_order_cancellation(uuid,boolean,text) from public,anon;
grant execute on function public.admin_review_order_cancellation(uuid,boolean,text) to authenticated;
