-- Run once in the SQL editor. People can cycle their nickname on the welcome screen.
-- Only names built from the two word lists are accepted.
create or replace function join_event(p_name text default null, p_avatar text default null, p_alias text default null)
returns people language plpgsql security definer set search_path = public as $fn$
declare me people; adj text; animal text; ok boolean := false;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into me from people where id = auth.uid();
  if found then return me; end if;
  if p_alias is not null then
    adj := split_part(p_alias, ' ', 1); animal := split_part(p_alias, ' ', 2);
    ok := adj = any (array['Neon','Velvet','Copper','Lunar','Amber','Indigo','Mossy','Scarlet','Golden','Cobalt','Pearl','Ember'])
      and animal = any (array['Otter','Heron','Lynx','Falcon','Fox','Badger','Ibis','Marten','Puffin','Stoat','Wren','Yak'])
      and p_alias = adj || ' ' || animal;
  end if;
  insert into people (id, alias, name, variant, avatar_seed)
  values (auth.uid(), case when ok then p_alias else _random_alias() end, nullif(trim(p_name), ''), 'A',
          coalesce(nullif(trim(p_avatar), ''), gen_random_uuid()::text))
  returning * into me;
  return me;
end $fn$;
grant execute on function join_event(text, text, text) to authenticated;
revoke execute on function join_event(text, text, text) from anon, public;
drop function if exists join_event(text, text);
