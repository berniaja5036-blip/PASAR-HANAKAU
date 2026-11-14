create or replace function public.buyer_confirm_order_received(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not (select public.current_user_has_role('buyer')) then
    raise exception 'Hanya akun pembeli aktif yang dapat mengonfirmasi penerimaan barang.';
  end if;

  update public.orders
     set buyer_received_at = coalesce(buyer_received_at, pg_catalog.now())
   where id = p_order_id
     and buyer_id = (select auth.uid())
     and status = 'delivered'
     and buyer_received_at is null;

  if not found then
    if exists (
      select 1 from public.orders
       where id = p_order_id
         and buyer_id = (select auth.uid())
         and status = 'delivered'
         and buyer_received_at is not null
    ) then
      raise exception 'Penerimaan barang sudah dikonfirmasi sebelumnya.';
    end if;
    raise exception 'Pesanan tidak ditemukan atau belum berstatus selesai.';
  end if;
end;
$function$;

create or replace function public.admin_review_commission_payment(
  p_invoice_id uuid,
  p_approve boolean,
  p_admin_note text default ''
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_invoice public.seller_commission_invoices%rowtype;
begin
  if not coalesce(public.is_admin(),false) then
    raise exception 'Hanya admin yang dapat memverifikasi pembayaran komisi.';
  end if;
  if p_approve is null then
    raise exception 'Keputusan verifikasi pembayaran wajib dipilih.';
  end if;

  select * into v_invoice
    from public.seller_commission_invoices
   where id = p_invoice_id
   for update;
  if not found or v_invoice.status <> 'payment_submitted' then
    raise exception 'Konfirmasi pembayaran tidak ditemukan atau sudah diproses.';
  end if;

  update public.seller_commission_invoices
     set status = case when p_approve then 'paid' else 'issued' end,
         admin_note = nullif(pg_catalog.btrim(coalesce(p_admin_note,'')),''),
         reviewed_by = (select auth.uid()),
         reviewed_at = pg_catalog.now()
   where id = p_invoice_id;

  if p_approve then
    update public.seller_commission_entries
       set status = 'paid'
     where invoice_id = p_invoice_id;
  end if;
end;
$function$;

revoke all on function public.buyer_confirm_order_received(uuid) from public, anon;
grant execute on function public.buyer_confirm_order_received(uuid) to authenticated;
revoke all on function public.admin_review_commission_payment(uuid,boolean,text) from public, anon;
grant execute on function public.admin_review_commission_payment(uuid,boolean,text) to authenticated;
