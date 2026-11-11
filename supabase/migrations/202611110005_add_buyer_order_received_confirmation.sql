alter table public.orders add column if not exists buyer_received_at timestamptz;

create or replace function public.buyer_confirm_order_received(p_order_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  update public.orders set buyer_received_at=coalesce(buyer_received_at,now())
   where id=p_order_id and buyer_id=(select auth.uid()) and status='delivered' and buyer_received_at is null;
  if not found then
    if exists(select 1 from public.orders where id=p_order_id and buyer_id=(select auth.uid()) and status='delivered' and buyer_received_at is not null) then
      raise exception 'Penerimaan barang sudah dikonfirmasi sebelumnya.';
    end if;
    raise exception 'Pesanan tidak ditemukan atau belum berstatus selesai.';
  end if;
end;
$$;
revoke all on function public.buyer_confirm_order_received(uuid) from public;
grant execute on function public.buyer_confirm_order_received(uuid) to authenticated;