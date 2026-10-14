-- Run once in the SQL editor. People choose their avatar on the welcome screen; the seed is stored
-- so their match sees the same face.
alter table people add column if not exists avatar_seed text;

create or replace function join_event(p_name text default null, p_avatar text default null)
returns people language plpgsql security definer set search_path = public as $$
declare me people;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into me from people where id = auth.uid();
  if found then return me; end if;
  insert into people (id, alias, name, variant, avatar_seed)
  values (auth.uid(), _random_alias(), nullif(trim(p_name), ''), 'A', coalesce(nullif(trim(p_avatar), ''), gen_random_uuid()::text))
  returning * into me;
  return me;
end $$;
grant execute on function join_event(text, text) to authenticated;
revoke execute on function join_event(text, text) from anon, public;
drop function if exists join_event(text);

create or replace function match_card(p_match uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m matches; v vendors; partner_id uuid; partner_alias text; partner_avatar text; my_slot int; c checkins;
begin
  select * into m from matches where id = p_match;
  if not found then raise exception 'no such match'; end if;
  if m.person_1 = auth.uid() then my_slot := 1; partner_id := m.person_2;
  elsif m.person_2 = auth.uid() then my_slot := 2; partner_id := m.person_1;
  else raise exception 'not your match'; end if;
  select * into v from vendors where id = m.vendor_id;
  if partner_id is not null then
    select coalesce(nullif(trim(name), ''), alias), coalesce(avatar_seed, alias) into partner_alias, partner_avatar from people where id = partner_id;
  end if;
  select * into c from checkins where match_id = p_match and person_id = auth.uid();
  return jsonb_build_object(
    'id', m.id, 'my_slot', my_slot,
    'partner_alias', partner_alias, 'partner_avatar', partner_avatar,
    'vendor_name', v.name, 'vendor_location', v.location,
    'status_1', m.status_1, 'status_2', m.status_2,
    'self_at', c.self_at, 'partner_at', c.partner_at,
    'created_at', m.created_at);
end $$;
