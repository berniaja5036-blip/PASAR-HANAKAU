\set ON_ERROR_STOP on

do $$
begin
  if (select count(*) from public.profile_roles where role='buyer' and status='active') <> 5 then
    raise exception 'Expected buyer role for all five non-admin profiles';
  end if;
  if not exists (select 1 from public.profile_roles where user_id='00000000-0000-0000-0000-000000000002' and role='seller' and status='active') then
    raise exception 'Approved seller role was not backfilled';
  end if;
  if not exists (select 1 from public.profile_roles where user_id='00000000-0000-0000-0000-000000000003' and role='driver' and status='active') then
    raise exception 'Previously approved driver role was not preserved';
  end if;
  if not exists (select 1 from public.profile_roles where user_id='00000000-0000-0000-0000-000000000005' and role='driver' and status='pending') then
    raise exception 'Pending driver application was not backfilled as pending';
  end if;
  if not exists (select 1 from public.profile_roles where user_id='00000000-0000-0000-0000-000000000004' and role='admin' and status='active') then
    raise exception 'Admin role was not backfilled';
  end if;
  if public.current_user_has_active_role('buyer') then
    raise exception 'No JWT identity should not have an active role';
  end if;
  if has_table_privilege('authenticated','public.profile_roles','UPDATE') then
    raise exception 'Authenticated must not receive UPDATE on profile_roles';
  end if;
  if has_table_privilege('anon','public.profile_roles','SELECT') then
    raise exception 'Anon must not receive SELECT on profile_roles';
  end if;
end $$;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
do $$
begin
  if (select count(*) from public.profile_roles) <> 1 then
    raise exception 'Buyer should only read their own role row';
  end if;
  if not public.current_user_has_active_role('buyer') then
    raise exception 'Active buyer role should be recognized';
  end if;
end $$;
reset role;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
do $$
begin
  if (select count(*) from public.profile_roles) <> 2 then
    raise exception 'Driver should read both buyer and driver roles';
  end if;
  if not public.current_user_has_active_role('driver') or not public.current_user_has_active_role('buyer') then
    raise exception 'Approved driver should have active buyer and driver roles';
  end if;
end $$;
reset role;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004';
do $$
begin
  if (select count(*) from public.profile_roles) <> 8 then
    raise exception 'Admin should be able to read all role rows';
  end if;
end $$;
reset role;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000006';
do $$
begin
  if public.current_user_has_active_role('buyer') then
    raise exception 'Suspended account must not have active role access';
  end if;
end $$;
reset role;

insert into public.profiles(id,role,account_status) values
('00000000-0000-0000-0000-000000000007','buyer','active');
do $$
begin
  if not exists (select 1 from public.profile_roles where user_id='00000000-0000-0000-0000-000000000007' and role='buyer' and status='active') then
    raise exception 'New buyer profile trigger did not create buyer role';
  end if;
end $$;

insert into public.seller_applications(id,user_id,status) values
('20000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','pending');
insert into public.shops(id,owner_id,status) values
('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','approved');
update public.seller_applications set status='approved',reviewed_by='00000000-0000-0000-0000-000000000004',reviewed_at=now()
where id='20000000-0000-0000-0000-000000000002';

insert into public.driver_applications(id,user_id,status) values
('30000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000001','pending');
insert into public.driver_profiles(id,approval_status) values
('00000000-0000-0000-0000-000000000001','approved');
update public.driver_applications set status='approved',reviewed_by='00000000-0000-0000-0000-000000000004',reviewed_at=now()
where id='30000000-0000-0000-0000-000000000003';

do $$
begin
  if not exists (select 1 from public.profile_roles where user_id='00000000-0000-0000-0000-000000000001' and role='seller' and status='active') then
    raise exception 'Seller application approval trigger did not activate seller role';
  end if;
  if not exists (select 1 from public.profile_roles where user_id='00000000-0000-0000-0000-000000000001' and role='driver' and status='active') then
    raise exception 'Driver application approval trigger did not activate driver role';
  end if;
end $$;

update public.driver_applications set status='rejected',reviewed_by='00000000-0000-0000-0000-000000000004',reviewed_at=now()
where id='30000000-0000-0000-0000-000000000002';
do $$
begin
  if not exists (select 1 from public.profile_roles where user_id='00000000-0000-0000-0000-000000000005' and role='driver' and status='rejected') then
    raise exception 'Rejected driver application did not update role status';
  end if;
end $$;

select 'profile_roles migration tests passed' as result;
