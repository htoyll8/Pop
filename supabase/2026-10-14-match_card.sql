-- Run once in the SQL editor after schema.sql. Adds the card view function and
-- makes a passed / timed-out match release the other person. (Also appended to schema.sql.)

-- 5. What the card shows: partner alias (A only), vendor name + location, both statuses, my slot.
create or replace function match_card(p_match uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m matches; v vendors; partner_id uuid; partner_alias text; my_slot int; c checkins;
begin
  select * into m from matches where id = p_match;
  if not found then raise exception 'no such match'; end if;
  if m.person_1 = auth.uid() then my_slot := 1; partner_id := m.person_2;
  elsif m.person_2 = auth.uid() then my_slot := 2; partner_id := m.person_1;
  else raise exception 'not your match'; end if;
  select * into v from vendors where id = m.vendor_id;
  if partner_id is not null then select alias into partner_alias from people where id = partner_id; end if;
  select * into c from checkins where match_id = p_match and person_id = auth.uid();
  return jsonb_build_object(
    'id', m.id, 'my_slot', my_slot,
    'partner_alias', partner_alias,
    'vendor_name', v.name, 'vendor_location', v.location,
    'status_1', m.status_1, 'status_2', m.status_2,
    'self_at', c.self_at, 'partner_at', c.partner_at,
    'created_at', m.created_at);
end $$;
grant execute on function match_card(uuid) to authenticated;
revoke execute on function match_card(uuid) from anon, public;

-- find_match: a match is live only if nobody has passed or timed out.
create or replace function find_match()
returns matches language plpgsql security definer set search_path = public as $$
declare
  me       people;
  partner  people;
  v        vendors;
  m        matches;
  timeout  interval := interval '10 minutes';
begin
  select * into me from people where id = auth.uid();
  if not found then raise exception 'join first'; end if;
  if not exists (select 1 from vendors) then raise exception 'no vendors configured'; end if;

  select * into m from matches
   where (person_1 = me.id or person_2 = me.id)
     and created_at > now() - timeout
     and status_1 in ('proposed','confirmed')
     and (status_2 is null or status_2 in ('proposed','confirmed'))
   order by created_at desc limit 1;
  if found then return m; end if;

  if me.variant = 'B' then
    select * into v from vendors order by last_assigned_at nulls first, random() limit 1 for update;
    update vendors set last_assigned_at = now() where id = v.id;
    insert into matches (person_1, vendor_id) values (me.id, v.id) returning * into m;
    return m;
  end if;

  select * into partner from people
   where variant = 'A' and waiting_since is not null and id <> me.id
   order by waiting_since asc limit 1 for update skip locked;
  if found then
    update people set waiting_since = null where id in (partner.id, me.id);
    select * into v from vendors order by last_assigned_at nulls first, random() limit 1 for update;
    update vendors set last_assigned_at = now() where id = v.id;
    insert into matches (person_1, person_2, vendor_id, status_1, status_2)
      values (partner.id, me.id, v.id, 'proposed', 'proposed') returning * into m;
    return m;
  end if;

  update people set waiting_since = coalesce(waiting_since, now()) where id = me.id;
  return null;
end $$;
