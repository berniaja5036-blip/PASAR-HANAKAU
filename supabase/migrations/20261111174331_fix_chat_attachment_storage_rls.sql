drop policy if exists chat_attachments_participant_read on storage.objects;
drop policy if exists chat_attachments_sender_upload on storage.objects;
drop policy if exists chat_attachments_sender_delete on storage.objects;

create policy chat_attachments_participant_read
on storage.objects for select to authenticated
using (
  bucket_id = 'chat-attachments'
  and exists (
    select 1
    from public.chat_conversations c
    join public.shops s on s.id = c.shop_id
    where c.id::text = (storage.foldername(objects.name))[1]
      and (c.buyer_id = (select auth.uid()) or s.owner_id = (select auth.uid()))
  )
);

create policy chat_attachments_sender_upload
on storage.objects for insert to authenticated
with check (
  bucket_id = 'chat-attachments'
  and (storage.foldername(objects.name))[2] = (select auth.uid())::text
  and exists (
    select 1
    from public.chat_conversations c
    join public.shops s on s.id = c.shop_id
    where c.id::text = (storage.foldername(objects.name))[1]
      and (c.buyer_id = (select auth.uid()) or s.owner_id = (select auth.uid()))
  )
);

create policy chat_attachments_sender_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'chat-attachments'
  and (storage.foldername(objects.name))[2] = (select auth.uid())::text
  and exists (
    select 1
    from public.chat_conversations c
    join public.shops s on s.id = c.shop_id
    where c.id::text = (storage.foldername(objects.name))[1]
      and (c.buyer_id = (select auth.uid()) or s.owner_id = (select auth.uid()))
  )
);