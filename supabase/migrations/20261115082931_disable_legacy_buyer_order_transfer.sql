-- Buyer orders are COD-only. Keep historical SELECT and admin-only management policies,
-- but prevent authenticated buyers from creating or resubmitting legacy bank-transfer proofs.
begin;
drop policy if exists order_payment_submissions_buyer_insert on public.order_payment_submissions;
drop policy if exists order_payment_submissions_buyer_resubmit on public.order_payment_submissions;
commit;
