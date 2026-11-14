create or replace function public.guard_order_payment_submission_update()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
 if not (select is_admin()) then
  if old.status <> 'rejected' or new.status <> 'submitted'
   or new.id is distinct from old.id or new.order_id is distinct from old.order_id
   or new.reviewed_at is not null or new.reviewed_by is not null
   or new.admin_note is not null or new.created_at is distinct from old.created_at then
   raise exception 'Pembeli hanya dapat mengirim ulang konfirmasi pembayaran yang ditolak';
  end if;
 end if;
 return new;
end; $$;