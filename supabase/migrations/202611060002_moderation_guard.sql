-- Prevent owners from approving their own stores/products.
create or replace function public.guard_moderated_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is distinct from old.status
     and not public.has_role('admin') then
    raise exception 'Only an administrator can change approval/publication status';
  end if;
  return new;
end;
$$;

create trigger stores_status_guard
before update on public.stores
for each row execute procedure public.guard_moderated_status();

create trigger products_status_guard
before update on public.products
for each row execute procedure public.guard_moderated_status();
