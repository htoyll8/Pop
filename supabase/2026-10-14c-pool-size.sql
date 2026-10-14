-- Run once in the SQL editor. How many people are in the mix right now (count only).
create or replace function pool_size()
returns int language sql security definer set search_path = public stable as $$
  select count(*)::int from people where waiting_since is not null and waiting_since > now() - interval '15 minutes';
$$;
grant execute on function pool_size() to authenticated;
revoke execute on function pool_size() from anon, public;
