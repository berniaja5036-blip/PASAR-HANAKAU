-- Pasar Hanakau: catat seluruh perubahan status pesanan secara otomatis.
create table if not exists public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  from_status text,
  to_status text not null,
  changed_by uuid references public.profiles(id) on delete set null,
  changed_at timestamptz not null default now()
);
create index if not exists order_status_history_order_time_idx
  on public.order_status_history(order_id, changed_at);
alter table public.order_status_history enable row level security;
grant select on public.order_status_history to authenticated;

drop policy if exists order_status_history_read_participants on public.order_status_history;
create policy order_status_history_read_participants
on public.order_status_history for select to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_status_history.order_id
      and (
        o.buyer_id = (select auth.uid())
        or (select public.is_admin())
        or (select public.seller_can_read_order(o.id))
        or exists (
          select 1 from public.deliveries d
          where d.order_id = o.id and d.driver_id = (select auth.uid())
        )
      )
  )
);

create or replace function public.record_order_status_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.order_status_history(order_id, from_status, to_status, changed_by)
    values (new.id, null, new.status, (select auth.uid()));
  elsif new.status is distinct from old.status then
    insert into public.order_status_history(order_id, from_status, to_status, changed_by)
    values (new.id, old.status, new.status, (select auth.uid()));
  end if;
  return new;
end;
$$;

drop trigger if exists orders_record_status_history on public.orders;
create trigger orders_record_status_history
after insert or update of status on public.orders
for each row execute function public.record_order_status_history();

insert into public.order_status_history(order_id, from_status, to_status, changed_by, changed_at)
select o.id, null, o.status, null, o.created_at
from public.orders o
where not exists (select 1 from public.order_status_history h where h.order_id = o.id);
