-- Notify active administrators when a new seller or driver application is submitted.
-- Notifications are delivered through the existing notifications -> push webhook pipeline.
create or replace function public.notify_admin_application_submissions()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_title text;
  v_body text;
  v_event_key text;
begin
  if coalesce(new.status, 'pending') <> 'pending' then
    return new;
  end if;

  if tg_table_name = 'seller_applications' then
    v_title := 'Pengajuan toko baru';
    v_body := 'Ada pengajuan toko baru yang menunggu pemeriksaan admin.';
    v_event_key := 'seller-application:' || new.id::text;
  elsif tg_table_name = 'driver_applications' then
    v_title := 'Pengajuan driver baru';
    v_body := 'Ada pengajuan driver baru yang menunggu pemeriksaan admin.';
    v_event_key := 'driver-application:' || new.id::text;
  else
    return new;
  end if;

  insert into public.notifications (user_id, title, body, target_path, event_key)
  select p.id, v_title, v_body, './#adminPanel', v_event_key || ':' || p.id::text
  from public.profiles p
  where p.role = 'admin'
    and p.account_status = 'active'
  on conflict (user_id, event_key) do nothing;

  return new;
end;
$function$;

revoke all on function public.notify_admin_application_submissions() from public, anon, authenticated;

drop trigger if exists notify_admin_new_seller_application on public.seller_applications;
create trigger notify_admin_new_seller_application
after insert on public.seller_applications
for each row execute function public.notify_admin_application_submissions();

drop trigger if exists notify_admin_new_driver_application on public.driver_applications;
create trigger notify_admin_new_driver_application
after insert on public.driver_applications
for each row execute function public.notify_admin_application_submissions();
