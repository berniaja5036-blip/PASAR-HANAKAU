-- Pasar Hanakau: pengunci periode penerbitan tagihan komisi.
-- Hanya periode bulan kalender sebelumnya (WIB) yang boleh diterbitkan.
-- Mencegah salah tekan menerbitkan periode berjalan atau periode lain.

create or replace function public.admin_generate_monthly_commission_invoices(
  p_period_start date,
  p_due_date date default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $ph$
declare
  v_count integer;
  v_allowed_period date;
begin
  if not coalesce(public.is_admin(),false) then
    raise exception 'Hanya admin yang dapat menerbitkan tagihan komisi.';
  end if;

  v_allowed_period := date_trunc(
    'month',
    (now() at time zone 'Asia/Jakarta') - interval '1 month'
  )::date;

  if p_period_start is null or extract(day from p_period_start) <> 1 then
    raise exception 'Periode tagihan harus menggunakan tanggal pertama bulan.';
  end if;

  if p_period_start <> v_allowed_period then
    raise exception 'Tagihan hanya dapat diterbitkan untuk bulan sebelumnya yang sudah selesai. Periode yang diizinkan saat ini: %.',
      to_char(v_allowed_period, 'YYYY-MM');
  end if;

  if p_due_date is not null and p_due_date < p_period_start then
    raise exception 'Tanggal jatuh tempo tidak valid.';
  end if;

  insert into public.seller_commission_invoices
    (seller_id,period_start,subtotal_amount,commission_amount,status,due_date)
  select seller_id,period_start,sum(basis_amount),sum(commission_amount),'issued',p_due_date
  from public.seller_commission_entries
  where period_start = p_period_start and status = 'accrued'
  group by seller_id,period_start
  on conflict (seller_id,period_start) do nothing;

  get diagnostics v_count = row_count;

  update public.seller_commission_entries e
     set invoice_id = i.id,status = 'invoiced'
    from public.seller_commission_invoices i
   where i.seller_id = e.seller_id
     and i.period_start = e.period_start
     and e.period_start = p_period_start
     and e.status = 'accrued'
     and i.status = 'issued';

  update public.seller_commission_invoices i
     set subtotal_amount = totals.subtotal_amount,
         commission_amount = totals.commission_amount
    from (
      select invoice_id,sum(basis_amount) as subtotal_amount,sum(commission_amount) as commission_amount
        from public.seller_commission_entries
       where period_start = p_period_start and invoice_id is not null
       group by invoice_id
    ) totals
   where i.id = totals.invoice_id and i.status = 'issued';

  return coalesce(v_count,0);
end;
$ph$;

revoke all on function public.admin_generate_monthly_commission_invoices(date,date) from public, anon;
grant execute on function public.admin_generate_monthly_commission_invoices(date,date) to authenticated;
