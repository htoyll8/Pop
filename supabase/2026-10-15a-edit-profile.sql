-- Run once in the SQL editor. Lets someone go back from the waiting screen, change their name,
-- nickname, or avatar, and rejoin. Their identity (auth.uid) is unchanged.
create or replace function update_profile(p_name text default null, p_avatar text default null, p_alias text default null)
returns people language plpgsql security definer set search_path = public as $fn$
declare me people; adj text; animal text; ok boolean := false;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_alias is not null then
    adj := split_part(p_alias, ' ', 1); animal := split_part(p_alias, ' ', 2);
    ok := adj = any (array['Neon','Velvet','Copper','Lunar','Amber','Indigo','Mossy','Scarlet','Golden','Cobalt','Pearl','Ember'])
      and animal = any (array['Otter','Heron','Lynx','Falcon','Fox','Badger','Ibis','Marten','Puffin','Stoat','Wren','Yak'])
      and p_alias = adj || ' ' || animal;
  end if;
  update people set
    name = nullif(trim(p_name), ''),
    avatar_seed = coalesce(nullif(trim(p_avatar), ''), avatar_seed),
    alias = case when ok then p_alias else alias end
  where id = auth.uid() returning * into me;
  if not found then raise exception 'join first'; end if;
  return me;
end $fn$;

create or replace function leave_pool()
returns void language sql security definer set search_path = public as $fn$
  update people set waiting_since = null where id = auth.uid()
$fn$;

grant execute on function update_profile(text, text, text), leave_pool() to authenticated;
revoke execute on function update_profile(text, text, text), leave_pool() from anon, public;
