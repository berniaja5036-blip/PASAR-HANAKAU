create table public.order_payment_submissions (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null unique references public.orders(id) on delete cascade,
 payment_method_id uuid not null references public.marketplace_payment_methods(id) on delete restrict,
 payment_reference text not null,
 status text not null default 'submitted' check (status in ('submitted','confirmed','rejected')),
 submitted_at timestamptz not null default now(),
 reviewed_at timestamptz,
 reviewed_by uuid references auth.users(id) on delete set null,
 admin_note text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint order_payment_reference_length check (length(trim(payment_reference)) between 4 and 120)
);
alter table public.order_payment_submissions enable row level security;
grant select, insert, update on public.order_payment_submissions to authenticated;
create policy order_payment_submissions_buyer_read on public.order_payment_submissions for select to authenticated using (
 exists(select 1 from public.orders o where o.id=order_id and o.buyer_id=(select auth.uid())) or (select is_admin())
);
create policy order_payment_submissions_buyer_insert on public.order_payment_submissions for insert to authenticated with check (
 status='submitted' and exists(select 1 from public.orders o where o.id=order_id and o.buyer_id=(select auth.uid()) and o.status <> 'cancelled')
 and exists(select 1 from public.marketplace_payment_methods m where m.id=payment_method_id and m.enabled=true)
);
create policy order_payment_submissions_buyer_resubmit on public.order_payment_submissions for update to authenticated
using (status='rejected' and exists(select 1 from public.orders o where o.id=order_id and o.buyer_id=(select auth.uid())))
with check (status='submitted' and exists(select 1 from public.orders o where o.id=order_id and o.buyer_id=(select auth.uid()) and o.status <> 'cancelled')
 and exists(select 1 from public.marketplace_payment_methods m where m.id=payment_method_id and m.enabled=true));
create policy order_payment_submissions_admin_manage on public.order_payment_submissions for all to authenticated using ((select is_admin())) with check ((select is_admin()));
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
create trigger guard_order_payment_submission_update before update on public.order_payment_submissions for each row execute function public.guard_order_payment_submission_update();
create or replace function public.buyer_submit_order_payment(p_order_id uuid,p_payment_method_id uuid,p_payment_reference text)
returns void language plpgsql security invoker set search_path = '' as $$
declare v_status text;
begin
 if (select auth.uid()) is null then raise exception 'Silakan masuk sebagai pembeli'; end if;
 if p_payment_reference is null or length(trim(p_payment_reference)) < 4 or length(trim(p_payment_reference)) > 120 then raise exception 'Referensi pembayaran harus 4 sampai 120 karakter'; end if;
 if not exists(select 1 from public.marketplace_payment_methods m where m.id=p_payment_method_id and m.enabled=true) then raise exception 'Metode pembayaran tidak aktif'; end if;
 if not exists(select 1 from public.orders o where o.id=p_order_id and o.buyer_id=(select auth.uid()) and o.status <> 'cancelled') then raise exception 'Pesanan tidak ditemukan atau tidak dapat dibayar'; end if;
 select status into v_status from public.order_payment_submissions where order_id=p_order_id;
 if v_status is null then
  insert into public.order_payment_submissions(order_id,payment_method_id,payment_reference,status) values(p_order_id,p_payment_method_id,trim(p_payment_reference),'submitted');
 elsif v_status='rejected' then
  update public.order_payment_submissions set payment_method_id=p_payment_method_id,payment_reference=trim(p_payment_reference),status='submitted',submitted_at=now(),reviewed_at=null,reviewed_by=null,admin_note=null,updated_at=now() where order_id=p_order_id;
 else raise exception 'Konfirmasi pembayaran sudah terkirim atau sudah diverifikasi';
 end if;
end; $$;
grant execute on function public.buyer_submit_order_payment(uuid,uuid,text) to authenticated;
