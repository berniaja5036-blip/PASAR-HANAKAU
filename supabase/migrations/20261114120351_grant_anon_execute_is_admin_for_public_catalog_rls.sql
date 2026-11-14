-- Public catalog RLS policies call is_admin() to distinguish administrators.
-- Grant only the boolean helper to anonymous visitors; with auth.uid() = NULL,
-- the function returns false and does not expose profile rows.
grant execute on function public.is_admin() to anon, authenticated;
