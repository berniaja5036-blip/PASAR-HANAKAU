create table public.chat_conversations (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  shop_id uuid not null references public.shops(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  unique (buyer_id, shop_id)
);
create index chat_conversations_buyer_last_idx on public.chat_conversations (buyer_id, last_message_at desc);
create index chat_conversations_shop_last_idx on public.chat_conversations (shop_id, last_message_at desc);

create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.chat_conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text,
  attachment_path text,
  attachment_name text,
  attachment_mime text,
  attachment_size bigint,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint chat_message_content_check check ((nullif(btrim(body), '') is not null) or attachment_path is not null),
  constraint chat_message_body_length_check check (body is null or char_length(body) <= 5000),
  constraint chat_attachment_metadata_check check (
    (attachment_path is null and attachment_name is null and attachment_mime is null and attachment_size is null)
    or
    (attachment_path is not null and attachment_name is not null and attachment_mime is not null
      and attachment_size between 1 and 10485760
      and attachment_path like conversation_id::text || '/' || sender_id::text || '/%'
      and attachment_mime in (
        'image/jpeg','image/png','image/webp','application/pdf','text/plain','text/csv',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-excel',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      ))
  )
);
create index chat_messages_conversation_created_idx on public.chat_messages (conversation_id, created_at);
create index chat_messages_sender_unread_idx on public.chat_messages (sender_id, read_at);

alter table public.chat_conversations enable row level security;
alter table public.chat_messages enable row level security;

create policy chat_conversations_participant_read on public.chat_conversations
for select to authenticated using (
  buyer_id=(select auth.uid()) or exists (
    select 1 from public.shops s where s.id=chat_conversations.shop_id and s.owner_id=(select auth.uid())
  )
);
create policy chat_conversations_buyer_create on public.chat_conversations
for insert to authenticated with check (
  buyer_id=(select auth.uid()) and exists (
    select 1 from public.shops s where s.id=chat_conversations.shop_id
      and s.status='approved' and s.owner_id<>(select auth.uid())
  )
);
create policy chat_messages_participant_read on public.chat_messages
for select to authenticated using (
  exists (
    select 1 from public.chat_conversations c left join public.shops s on s.id=c.shop_id
    where c.id=chat_messages.conversation_id
      and (c.buyer_id=(select auth.uid()) or s.owner_id=(select auth.uid()))
  )
);
create policy chat_messages_participant_send on public.chat_messages
for insert to authenticated with check (
  sender_id=(select auth.uid()) and exists (
    select 1 from public.chat_conversations c left join public.shops s on s.id=c.shop_id
    where c.id=chat_messages.conversation_id
      and (c.buyer_id=(select auth.uid()) or s.owner_id=(select auth.uid()))
  )
);
create policy chat_messages_recipient_mark_read on public.chat_messages
for update to authenticated using (
  sender_id<>(select auth.uid()) and exists (
    select 1 from public.chat_conversations c left join public.shops s on s.id=c.shop_id
    where c.id=chat_messages.conversation_id
      and (c.buyer_id=(select auth.uid()) or s.owner_id=(select auth.uid()))
  )
) with check (
  sender_id<>(select auth.uid()) and exists (
    select 1 from public.chat_conversations c left join public.shops s on s.id=c.shop_id
    where c.id=chat_messages.conversation_id
      and (c.buyer_id=(select auth.uid()) or s.owner_id=(select auth.uid()))
  )
);

revoke all on public.chat_conversations from anon, authenticated;
revoke all on public.chat_messages from anon, authenticated;
grant select, insert on public.chat_conversations to authenticated;
grant select, insert on public.chat_messages to authenticated;
grant update (read_at) on public.chat_messages to authenticated;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('chat-attachments','chat-attachments',false,10485760,array[
  'image/jpeg','image/png','image/webp','application/pdf','text/plain','text/csv',
  'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
])
on conflict (id) do update set public=false,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;

create policy chat_attachments_participant_read on storage.objects for select to authenticated
using (
  bucket_id='chat-attachments' and exists (
    select 1 from public.chat_conversations c left join public.shops s on s.id=c.shop_id
    where c.id::text=(storage.foldername(name))[1]
      and (c.buyer_id=(select auth.uid()) or s.owner_id=(select auth.uid()))
  )
);
create policy chat_attachments_sender_upload on storage.objects for insert to authenticated
with check (
  bucket_id='chat-attachments' and (storage.foldername(name))[2]=(select auth.uid())::text
  and exists (
    select 1 from public.chat_conversations c left join public.shops s on s.id=c.shop_id
    where c.id::text=(storage.foldername(name))[1]
      and (c.buyer_id=(select auth.uid()) or s.owner_id=(select auth.uid()))
  )
);
create policy chat_attachments_sender_delete on storage.objects for delete to authenticated
using (
  bucket_id='chat-attachments' and (storage.foldername(name))[2]=(select auth.uid())::text
  and exists (
    select 1 from public.chat_conversations c left join public.shops s on s.id=c.shop_id
    where c.id::text=(storage.foldername(name))[1]
      and (c.buyer_id=(select auth.uid()) or s.owner_id=(select auth.uid()))
  )
);

create or replace function public.on_chat_message_created()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare
  v_conversation public.chat_conversations%rowtype;
  v_shop_owner uuid;
  v_recipient uuid;
  v_title text;
  v_preview text;
  v_target text;
begin
  select * into v_conversation from public.chat_conversations where id=new.conversation_id;
  if not found then return new; end if;
  select owner_id into v_shop_owner from public.shops where id=v_conversation.shop_id;
  if new.sender_id=v_conversation.buyer_id then
    v_recipient:=v_shop_owner; v_title:='Pesan baru dari pembeli'; v_target:='./#seller-chat';
  else
    v_recipient:=v_conversation.buyer_id; v_title:='Pesan baru dari toko'; v_target:='./#buyer-chat';
  end if;
  v_preview:=case when nullif(btrim(new.body),'') is not null then left(btrim(new.body),120) else 'Mengirim lampiran' end;
  update public.chat_conversations set last_message_at=new.created_at,updated_at=now() where id=new.conversation_id;
  if v_recipient is not null then
    insert into public.notifications(user_id,title,body,target_path,event_key)
    values(v_recipient,v_title,v_preview,v_target,'chat-message:'||new.id::text)
    on conflict(user_id,event_key) do nothing;
  end if;
  return new;
end
$function$;
revoke all on function public.on_chat_message_created() from public, anon, authenticated;
create trigger trg_chat_message_created after insert on public.chat_messages
for each row execute function public.on_chat_message_created();
