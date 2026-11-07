-- Pasar Hanakau: admin dapat memperbarui status pesanan melalui RPC aman.
-- Jalankan sekali di Supabase SQL Editor setelah migrasi checkout.

create or replace function public.admin_update_order_status(
  p_order_id uuid,
  p_new_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_status text;
  v_allowed boolean := false;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'Hanya admin yang dapat mengubah status pesanan.';
  end if;

  if p_new_status not in ('confirmed','ready_for_pickup','picked_up','delivered','cancelled') then
    raise exception 'Status pesanan tidak valid.';
  end if;

  select o.status
    into v_current_status
    from public.orders o
   where o.id = p_order_id
   for update;

  if not found then
    raise exception 'Pesanan tidak ditemukan.';
  end if;

  v_allowed :=
    (v_current_status = 'pending' and p_new_status in ('confirmed','cancelled'))
    or (v_current_status = 'confirmed' and p_new_status in ('ready_for_pickup','cancelled'))
    or (v_current_status = 'ready_for_pickup' and p_new_status = 'picked_up')
    or (v_current_status = 'picked_up' and p_new_status = 'delivered');

  if not v_allowed then
    raise exception 'Perubahan status dari % ke % tidak diizinkan.', v_current_status, p_new_status;
  end if;

  update public.orders
     set status = p_new_status
   where id = p_order_id;
end;
$$;

revoke all on function public.admin_update_order_status(uuid, text) from public, anon;
grant execute on function public.admin_update_order_status(uuid, text) to authenticated;
