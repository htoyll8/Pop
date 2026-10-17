-- Run once in the SQL editor (after 2026-10-17b-text-me.sql).
-- The "Text me" list becomes a queue: when someone searches and nobody is live, they're paired with the
-- person who has waited longest for a text. The dashboard then shows that person as "matched, text now",
-- and the texted link opens straight onto the match. These matches get a longer Let's go window (8 min).
alter table matches add column if not exists queued boolean not null default false;
alter table text_me add column if not exists match_id uuid;

create or replace function find_match()
returns matches language plpgsql security definer set search_path = public as $fn$
declare
  me       people;
  partner  people;
  q        text_me;
  v        vendors;
  m        matches;
  timeout  interval := interval '10 minutes';
begin
  select * into me from people where id = auth.uid();
  if not found then raise exception 'join first'; end if;
  if not exists (select 1 from vendors) then raise exception 'no vendors configured'; end if;
  update people set last_seen = now() where id = me.id;

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

  select p.* into partner from people p
   where p.variant = 'A' and p.waiting_since is not null and p.id <> me.id
     and p.last_seen > now() - interval '30 seconds'          -- only people actually searching now
     and not exists (select 1 from matches x
                      where (x.person_1 = me.id and x.person_2 = p.id)
                         or (x.person_1 = p.id and x.person_2 = me.id))
   order by p.waiting_since asc limit 1 for update skip locked;
  if found then
    update people set waiting_since = null where id in (partner.id, me.id);
    select * into v from vendors order by last_assigned_at nulls first, random() limit 1 for update;
    update vendors set last_assigned_at = now() where id = v.id;
    insert into matches (person_1, person_2, vendor_id, status_1, status_2)
      values (partner.id, me.id, v.id, 'proposed', 'proposed') returning * into m;
    delete from text_me where person_id in (partner.id, me.id) and texted_at is null and match_id is null;   -- matched live: no text needed
    return m;
  end if;

  -- nobody live: pair with whoever has waited longest for a text (asked in the last 2 hours, never paired before)
  select t.* into q from text_me t
   where t.texted_at is null and t.match_id is null and t.person_id is not null and t.person_id <> me.id
     and t.created_at > now() - interval '2 hours'
     and exists (select 1 from people p where p.id = t.person_id
                  and (p.last_seen is null or p.last_seen < now() - interval '30 seconds'))   -- still searching live? the live pool handles them
     and not exists (select 1 from matches x
                      where (x.person_1 = me.id and x.person_2 = t.person_id)
                         or (x.person_1 = t.person_id and x.person_2 = me.id))
     and not exists (select 1 from matches x                  -- not already in a live match
                      where (x.person_1 = t.person_id or x.person_2 = t.person_id)
                        and x.created_at > now() - timeout
                        and x.status_1 in ('proposed','confirmed') and coalesce(x.status_2, 'proposed') in ('proposed','confirmed'))
   order by t.created_at asc limit 1 for update skip locked;
  if found then
    update people set waiting_since = null where id in (q.person_id, me.id);
    select * into v from vendors order by last_assigned_at nulls first, random() limit 1 for update;
    update vendors set last_assigned_at = now() where id = v.id;
    insert into matches (person_1, person_2, vendor_id, status_1, status_2, queued)
      values (q.person_id, me.id, v.id, 'proposed', 'proposed', true) returning * into m;
    update text_me set match_id = m.id where id = q.id;
    return m;
  end if;

  update people set waiting_since = coalesce(waiting_since, now()) where id = me.id;
  return null;
end $fn$;

-- the card also says whether the match came from the text queue (the app gives those a longer timer)
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
    'met_at', m.met_at, 'queued', m.queued,
    'created_at', m.created_at);
end $fn$;

-- dashboard list: matched people first (text them now), then the rest of the queue
create or replace function dash_text_list(p_key text)
returns jsonb language plpgsql security definer set search_path = public stable as $fn$
begin
  if p_key is null or not exists (select 1 from dash_keys where key = p_key) then raise exception 'bad key'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'phone', t.phone, 'at', t.created_at,
            'name', coalesce(nullif(trim(p.name), ''), p.alias),
            'matched', t.match_id is not null, 'matched_at', m.created_at,
            'with', coalesce(nullif(trim(o.name), ''), o.alias))
            order by (t.match_id is null), t.created_at)
         from text_me t left join people p on p.id = t.person_id
         left join matches m on m.id = t.match_id
         left join people o on o.id = case when m.person_1 = t.person_id then m.person_2 else m.person_1 end
        where t.texted_at is null and (t.match_id is null or m.created_at > now() - interval '10 minutes')), '[]');
end $fn$;
