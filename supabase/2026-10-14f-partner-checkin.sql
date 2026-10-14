-- Run once in the SQL editor. The card now also says whether your match has checked in at the booth.
create or replace function match_card(p_match uuid)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare m matches; v vendors; partner_id uuid; partner_alias text; partner_avatar text; partner_self timestamptz; my_slot int; c checkins;
begin
  select * into m from matches where id = p_match;
  if not found then raise exception 'no such match'; end if;
  if m.person_1 = auth.uid() then my_slot := 1; partner_id := m.person_2;
  elsif m.person_2 = auth.uid() then my_slot := 2; partner_id := m.person_1;
  else raise exception 'not your match'; end if;
  select * into v from vendors where id = m.vendor_id;
  if partner_id is not null then
    select coalesce(nullif(trim(name), ''), alias), coalesce(avatar_seed, alias) into partner_alias, partner_avatar from people where id = partner_id;
    select self_at into partner_self from checkins where match_id = p_match and person_id = partner_id;
  end if;
  select * into c from checkins where match_id = p_match and person_id = auth.uid();
  return jsonb_build_object(
    'id', m.id, 'my_slot', my_slot,
    'partner_alias', partner_alias, 'partner_avatar', partner_avatar, 'partner_self_at', partner_self,
    'vendor_name', v.name, 'vendor_location', v.location,
    'status_1', m.status_1, 'status_2', m.status_2,
    'self_at', c.self_at, 'partner_at', c.partner_at,
    'created_at', m.created_at);
end $fn$;
