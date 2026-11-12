drop policy if exists active_account_required on storage.objects;
create policy active_account_required on storage.objects
as restrictive
for all
to authenticated
using ((select public.current_user_is_active()))
with check ((select public.current_user_is_active()));