-- Pasar Hanakau: permintaan pembatalan pesanan oleh pembeli dan pemeriksaan admin.
-- Jalankan sekali di Supabase SQL Editor setelah migrasi 014.

create table if not exists public.order_cancellation_requests (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  buyer_id uuid not null references public.profiles(id) on delete restrict,
  reason text not null check (length(trim(reason)) between 5 and 500),
  status text not null default 'pending'
    check (status in ('pending','approved','rejected')),
  admin_note text,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists order_cancellation_one_pending_idx
  on public.order_cancellation_requests(order_id)
  where status = 'pending';
create index if not exists order_cancellation_buyer_time_idx
  on public.order_cancellation_requests(buyer_id, created_at desc);

alter table public.order_cancellation_requests enable row level security;
grant select on public.order_cancellation_requests to authenticated;

drop policy if exists order_cancellation_read_participants
  on public.order_cancellation_requests;
create policy order_cancellation_read_participants
on public.order_cancellation_requests for select to authenticated
using (buyer_id = (select auth.uid()) or (select public.is_admin()));

create or replace function public.buyer_request_order_cancellation(
  p_order_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_request_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Silakan masuk terlebih dahulu.';
  end if;
  if length(trim(coalesce(p_reason,''))) < 5
     or length(trim(coalesce(p_reason,''))) > 500 then
    raise exception 'Alasan pembatalan harus berisi 5 sampai 500 karakter.';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id and buyer_id = (select auth.uid())
  for update;

  if not found then
    raise exception 'Pesanan tidak ditemukan untuk akun pembeli ini.';
  end if;
  if v_order.status not in ('pending','confirmed') then
    raise exception 'Pembatalan hanya dapat diajukan sebelum pesanan disiapkan untuk driver.';
  end if;

  insert into public.order_cancellation_requests(order_id,buyer_id,reason)
  values (p_order_id,(select auth.uid()),trim(p_reason))
  returning id into v_request_id;

  return v_request_id;
exception
  when unique_violation then
    raise exception 'Masih ada permintaan pembatalan yang menunggu pemeriksaan admin.';
end;
$$;

revoke all on function public.buyer_request_order_cancellation(uuid,text)
  from public, anon;
grant execute on function public.buyer_request_order_cancellation(uuid,text)
  to authenticated;

create or replace function public.admin_review_order_cancellation(
  p_request_id uuid,
  p_approve boolean,
  p_admin_note text default ''
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.order_cancellation_requests%rowtype;
  v_order public.orders%rowtype;
begin
  if not coalesce(public.is_admin(),false) then
    raise exception 'Hanya admin yang dapat memproses pembatalan.';
  end if;

  select * into v_request
  from public.order_cancellation_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Permintaan pembatalan tidak ditemukan.';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'Permintaan ini sudah diproses.';
  end if;

  select * into v_order
  from public.orders
  where id = v_request.order_id
  for update;

  if not found then
    raise exception 'Pesanan tidak ditemukan.';
  end if;

  if p_approve then
    if v_order.status not in ('pending','confirmed') then
      raise exception 'Pesanan sudah masuk tahap persiapan/pengiriman dan tidak dapat dibatalkan melalui permintaan ini.';
    end if;

    -- Kembalikan stok secara atomik ketika pembatalan disetujui.
    update public.products p
       set stock = p.stock + item_totals.quantity
      from (
        select product_id, sum(quantity)::integer as quantity
        from public.order_items
        where order_id = v_order.id and product_id is not null
        group by product_id
      ) item_totals
     where p.id = item_totals.product_id;

    update public.orders set status = 'cancelled' where id = v_order.id;
    update public.deliveries
       set status = 'failed',
           delivery_notes = 'Pesanan dibatalkan setelah persetujuan admin.'
     where order_id = v_order.id and status = 'waiting';
  end if;

  update public.order_cancellation_requests
     set status = case when p_approve then 'approved' else 'rejected' end,
         admin_note = nullif(trim(coalesce(p_admin_note,'')),''),
         reviewed_by = (select auth.uid()),
         reviewed_at = now()
   where id = v_request.id;
end;
$$;

revoke all on function public.admin_review_order_cancellation(uuid,boolean,text)
  from public, anon;
grant execute on function public.admin_review_order_cancellation(uuid,boolean,text)
  to authenticated;
