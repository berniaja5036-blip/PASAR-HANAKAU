\set ON_ERROR_STOP on

insert into public.products(id, stock) values
  ('20000000-0000-4000-8000-000000000001', 10),
  ('20000000-0000-4000-8000-000000000002', 4);

insert into public.orders(id, status) values
  ('10000000-0000-4000-8000-000000000001', 'pending'),
  ('10000000-0000-4000-8000-000000000002', 'confirmed'),
  ('10000000-0000-4000-8000-000000000003', 'pending'),
  ('10000000-0000-4000-8000-000000000004', 'ready_for_pickup'),
  ('10000000-0000-4000-8000-000000000005', 'ready_for_pickup'),
  ('10000000-0000-4000-8000-000000000006', 'ready_for_pickup'),
  ('10000000-0000-4000-8000-000000000007', 'ready_for_pickup'),
  ('10000000-0000-4000-8000-000000000008', 'ready_for_pickup'),
  ('10000000-0000-4000-8000-000000000009', 'pending'),
  ('10000000-0000-4000-8000-000000000010', 'picked_up'),
  ('10000000-0000-4000-8000-000000000011', 'pending');

insert into public.order_items(order_id, product_id, quantity) values
  ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 2),
  ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 3),
  ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002', 1),
  ('10000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', 2);

insert into public.order_cancellation_requests(order_id, status) values
  ('10000000-0000-4000-8000-000000000003', 'pending');

insert into public.deliveries(order_id, status, driver_id) values
  ('10000000-0000-4000-8000-000000000001', 'waiting', null),
  ('10000000-0000-4000-8000-000000000002', 'assigned', null),
  ('10000000-0000-4000-8000-000000000004', 'waiting', null),
  ('10000000-0000-4000-8000-000000000005', 'waiting', null),
  ('10000000-0000-4000-8000-000000000006', 'waiting', null),
  ('10000000-0000-4000-8000-000000000007', 'waiting', null),
  ('10000000-0000-4000-8000-000000000008', 'waiting', null),
  ('10000000-0000-4000-8000-000000000009', 'waiting', null),
  ('10000000-0000-4000-8000-000000000010', 'picked_up', '30000000-0000-4000-8000-000000000001');

-- Cancellation must fail closed for non-admin callers and leave stock untouched.
select pg_catalog.set_config('test.is_admin', 'false', false);
do $$
declare
  v_error text;
begin
  begin
    perform public.admin_update_order_status(
      '10000000-0000-4000-8000-000000000001', 'cancelled'
    );
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is null or v_error not like '%Hanya admin%' then
    raise exception 'Expected non-admin cancellation to be rejected; got: %', coalesce(v_error, 'no error');
  end if;
  if (select stock from public.products where id = '20000000-0000-4000-8000-000000000001') <> 10 then
    raise exception 'Unauthorized cancellation changed product stock.';
  end if;
end;
$$;

-- Admin cancellation restores aggregated quantities once and fails waiting delivery.
select pg_catalog.set_config('test.is_admin', 'true', false);
select public.admin_update_order_status(
  '10000000-0000-4000-8000-000000000001', 'cancelled'
);
do $$
declare
  v_error text;
begin
  if (select status from public.orders where id = '10000000-0000-4000-8000-000000000001') <> 'cancelled' then
    raise exception 'Pending order was not cancelled.';
  end if;
  if (select stock from public.products where id = '20000000-0000-4000-8000-000000000001') <> 15 then
    raise exception 'Duplicate order lines were not aggregated when restoring stock.';
  end if;
  if (select stock from public.products where id = '20000000-0000-4000-8000-000000000002') <> 5 then
    raise exception 'Stock for the second product was not restored.';
  end if;
  if (select status from public.deliveries where order_id = '10000000-0000-4000-8000-000000000001') <> 'failed' then
    raise exception 'Waiting delivery was not failed after cancellation.';
  end if;

  begin
    perform public.admin_update_order_status(
      '10000000-0000-4000-8000-000000000001', 'cancelled'
    );
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is null then
    raise exception 'Repeated cancellation unexpectedly succeeded.';
  end if;
  if (select stock from public.products where id = '20000000-0000-4000-8000-000000000001') <> 15 then
    raise exception 'Repeated cancellation restored stock more than once.';
  end if;
end;
$$;

-- Confirmed-order cancellation restores stock and fails an assigned delivery.
select public.admin_update_order_status(
  '10000000-0000-4000-8000-000000000002', 'cancelled'
);
do $$
begin
  if (select status from public.orders where id = '10000000-0000-4000-8000-000000000002') <> 'cancelled' then
    raise exception 'Confirmed order was not cancelled.';
  end if;
  if (select stock from public.products where id = '20000000-0000-4000-8000-000000000002') <> 7 then
    raise exception 'Confirmed-order stock was not restored.';
  end if;
  if (select status from public.deliveries where order_id = '10000000-0000-4000-8000-000000000002') <> 'failed' then
    raise exception 'Assigned delivery was not failed after cancellation.';
  end if;
end;
$$;

-- A pending cancellation request blocks confirmation; valid transitions remain allowed.
do $$
declare
  v_error text;
begin
  begin
    perform public.admin_update_order_status(
      '10000000-0000-4000-8000-000000000003', 'confirmed'
    );
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is null or v_error not like '%permintaan pembatalan%' then
    raise exception 'Pending cancellation request did not block confirmation.';
  end if;
  if (select status from public.orders where id = '10000000-0000-4000-8000-000000000003') <> 'pending' then
    raise exception 'Blocked confirmation changed order status.';
  end if;

  perform public.admin_update_order_status(
    '10000000-0000-4000-8000-000000000011', 'confirmed'
  );
  perform public.admin_update_order_status(
    '10000000-0000-4000-8000-000000000011', 'ready_for_pickup'
  );
  if (select status from public.orders where id = '10000000-0000-4000-8000-000000000011') <> 'ready_for_pickup' then
    raise exception 'Allowed pending -> confirmed -> ready_for_pickup transitions failed.';
  end if;

  v_error := null;
  begin
    perform public.admin_update_order_status(
      '10000000-0000-4000-8000-000000000004', 'cancelled'
    );
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is null then
    raise exception 'Ready-for-pickup order was incorrectly cancellable through admin status RPC.';
  end if;
end;
$$;

-- Driver fixtures: one busy driver, one available driver, one missing a document,
-- and one suspended account. All document paths are private and owner-prefixed.
insert into public.profiles(id, role, account_status) values
  ('30000000-0000-4000-8000-000000000001', 'driver', 'active'),
  ('30000000-0000-4000-8000-000000000002', 'driver', 'active'),
  ('30000000-0000-4000-8000-000000000003', 'driver', 'active'),
  ('30000000-0000-4000-8000-000000000004', 'driver', 'suspended');

insert into public.driver_profiles(id, approval_status) values
  ('30000000-0000-4000-8000-000000000001', 'approved'),
  ('30000000-0000-4000-8000-000000000002', 'approved'),
  ('30000000-0000-4000-8000-000000000003', 'approved'),
  ('30000000-0000-4000-8000-000000000004', 'approved');

insert into public.driver_applications(user_id, status, ktp_image_path, face_image_path) values
  ('30000000-0000-4000-8000-000000000001', 'approved',
   '30000000-0000-4000-8000-000000000001/ktp.jpg',
   '30000000-0000-4000-8000-000000000001/face.jpg'),
  ('30000000-0000-4000-8000-000000000002', 'approved',
   '30000000-0000-4000-8000-000000000002/ktp.jpg',
   '30000000-0000-4000-8000-000000000002/face.jpg'),
  ('30000000-0000-4000-8000-000000000003', 'approved',
   '30000000-0000-4000-8000-000000000003/ktp.jpg',
   '30000000-0000-4000-8000-000000000003/face.jpg'),
  ('30000000-0000-4000-8000-000000000004', 'approved',
   '30000000-0000-4000-8000-000000000004/ktp.jpg',
   '30000000-0000-4000-8000-000000000004/face.jpg');

insert into storage.objects(bucket_id, name) values
  ('driver-private-documents', '30000000-0000-4000-8000-000000000001/ktp.jpg'),
  ('driver-private-documents', '30000000-0000-4000-8000-000000000001/face.jpg'),
  ('driver-private-documents', '30000000-0000-4000-8000-000000000002/ktp.jpg'),
  ('driver-private-documents', '30000000-0000-4000-8000-000000000002/face.jpg'),
  ('driver-private-documents', '30000000-0000-4000-8000-000000000003/ktp.jpg'),
  ('driver-private-documents', '30000000-0000-4000-8000-000000000004/ktp.jpg'),
  ('driver-private-documents', '30000000-0000-4000-8000-000000000004/face.jpg');

-- The already-picked-up task makes driver 1 busy before this dispatch attempt.
-- Driver 2 starts available and may receive exactly one active assignment.
select public.admin_assign_delivery(
  '10000000-0000-4000-8000-000000000004',
  '30000000-0000-4000-8000-000000000002'
);

do $$
declare
  v_error text;
begin
  if not exists (
    select 1 from public.deliveries
    where order_id = '10000000-0000-4000-8000-000000000004'
      and driver_id = '30000000-0000-4000-8000-000000000002'
      and status = 'assigned'
      and assigned_at is not null
  ) then
    raise exception 'Eligible driver was not assigned to a ready order.';
  end if;

  begin
    perform public.admin_assign_delivery(
      '10000000-0000-4000-8000-000000000005',
      '30000000-0000-4000-8000-000000000002'
    );
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is null or v_error not like '%sedang bertugas%' then
    raise exception 'A driver with an active task was allowed to receive a second task.';
  end if;
  if (select driver_id from public.deliveries where order_id = '10000000-0000-4000-8000-000000000005') is not null then
    raise exception 'Failed second assignment changed the delivery.';
  end if;

  v_error := null;
  begin
    perform public.admin_assign_delivery(
      '10000000-0000-4000-8000-000000000006',
      '30000000-0000-4000-8000-000000000003'
    );
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is null or v_error not like '%Dokumen identitas driver belum lengkap%' then
    raise exception 'Driver missing a private identity document was allowed to receive a task.';
  end if;

  v_error := null;
  begin
    perform public.admin_assign_delivery(
      '10000000-0000-4000-8000-000000000007',
      '30000000-0000-4000-8000-000000000004'
    );
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is null or v_error not like '%tidak aktif%' then
    raise exception 'Suspended driver account was allowed to receive a task.';
  end if;

  v_error := null;
  begin
    perform public.admin_assign_delivery(
      '10000000-0000-4000-8000-000000000008',
      '30000000-0000-4000-8000-000000000001'
    );
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is null or v_error not like '%sedang bertugas%' then
    raise exception 'Driver with a different active task was allowed to receive a second task.';
  end if;

  v_error := null;
  begin
    perform public.admin_assign_delivery(
      '10000000-0000-4000-8000-000000000009',
      '30000000-0000-4000-8000-000000000002'
    );
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is null or v_error not like '%harus berstatus Siap dijemput%' then
    raise exception 'A non-ready order was allowed to be assigned.';
  end if;
end;
$$;

-- Only the assigned, active and approved driver may advance a task.
-- The pickup and delivery transitions update both delivery and order atomically.
select pg_catalog.set_config('test.user_id', '30000000-0000-4000-8000-000000000002', false);
select pg_catalog.set_config('test.account_active', 'true', false);
select public.driver_update_delivery_status(
  (select id from public.deliveries where order_id = '10000000-0000-4000-8000-000000000004'),
  'picked_up',
  'Barang sudah dijemput dari toko.'
);
do $test$
begin
  if (select status from public.deliveries where order_id = '10000000-0000-4000-8000-000000000004') <> 'picked_up' then
    raise exception 'Driver pickup did not advance the delivery.';
  end if;
  if (select status from public.orders where id = '10000000-0000-4000-8000-000000000004') <> 'picked_up' then
    raise exception 'Driver pickup did not advance the order.';
  end if;
  if (select pickup_notes from public.deliveries where order_id = '10000000-0000-4000-8000-000000000004') <> 'Barang sudah dijemput dari toko.' then
    raise exception 'Pickup note was not persisted.';
  end if;
end;
$test$;

select public.driver_update_delivery_status(
  (select id from public.deliveries where order_id = '10000000-0000-4000-8000-000000000004'),
  'delivered',
  'Barang diterima pembeli.'
);
do $test$
declare
  v_error text;
begin
  if (select status from public.deliveries where order_id = '10000000-0000-4000-8000-000000000004') <> 'delivered' then
    raise exception 'Driver delivery did not complete the task.';
  end if;
  if (select status from public.orders where id = '10000000-0000-4000-8000-000000000004') <> 'delivered' then
    raise exception 'Driver delivery did not complete the order.';
  end if;
  if (select delivery_notes from public.deliveries where order_id = '10000000-0000-4000-8000-000000000004') <> 'Barang diterima pembeli.' then
    raise exception 'Delivery note was not persisted.';
  end if;

  begin
    perform public.driver_update_delivery_status(
      (select id from public.deliveries where order_id = '10000000-0000-4000-8000-000000000004'),
      'picked_up',
      ''
    );
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is null then
    raise exception 'A completed delivery accepted an invalid backward transition.';
  end if;
end;
$test$;

-- A different driver cannot mutate another driver's delivery, and inactive accounts fail closed.
select pg_catalog.set_config('test.user_id', '30000000-0000-4000-8000-000000000001', false);
do $test$
declare
  v_error text;
begin
  begin
    perform public.driver_update_delivery_status(
      (select id from public.deliveries where order_id = '10000000-0000-4000-8000-000000000004'),
      'delivered',
      ''
    );
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is null or v_error not like '%tidak ditemukan untuk akun driver ini%' then
    raise exception 'A different driver was allowed to update an unassigned delivery.';
  end if;
end;
$test$;

select pg_catalog.set_config('test.user_id', '30000000-0000-4000-8000-000000000002', false);
select pg_catalog.set_config('test.account_active', 'false', false);
do $test$
declare
  v_error text;
begin
  begin
    perform public.driver_update_delivery_status(
      (select id from public.deliveries where order_id = '10000000-0000-4000-8000-000000000004'),
      'delivered',
      ''
    );
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is null or v_error not like '%Akun tidak aktif%' then
    raise exception 'An inactive account was allowed to update a delivery.';
  end if;
end;
$test$;

-- Dispatch must also fail closed for non-admin callers.
select pg_catalog.set_config('test.is_admin', 'false', false);
do $$
declare
  v_error text;
begin
  begin
    perform public.admin_assign_delivery(
      '10000000-0000-4000-8000-000000000005',
      '30000000-0000-4000-8000-000000000002'
    );
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is null or v_error not like '%Hanya admin%' then
    raise exception 'Non-admin driver assignment was not rejected.';
  end if;
end;
$$;

select 'Transactional order cancellation and guarded driver assignment tests passed.' as result;
