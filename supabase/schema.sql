-- Crosspaths: Saturday event schema. Run once in the Supabase SQL editor.
-- Identity: Supabase anonymous sign-in. Each phone gets an auth user; auth.uid() is the person id.
-- Phones never write tables directly. All writes go through the functions at the bottom.

create extension if not exists pgcrypto;

-- ---------- tables ----------

create table if not exists people (
  id            uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  seq           bigserial,                                  -- sign-up order; drives variant
  alias         text not null,
  name          text,
  variant       text not null check (variant in ('A','B')),
  waiting_since timestamptz,                                -- non-null while in the A pool
  created_at    timestamptz not null default now()
);

create table if not exists vendors (
  id               serial primary key,
  name             text not null,
  location         text not null,                           -- shown on the rendezvous card
  last_assigned_at timestamptz
);

create table if not exists matches (
  id         uuid primary key default gen_random_uuid(),
  person_1   uuid not null references people(id),
  person_2   uuid references people(id),                    -- null in variant B
  vendor_id  int  not null references vendors(id),
  status_1   text not null default 'proposed' check (status_1 in ('proposed','confirmed','passed','timed_out')),
  status_2   text          check (status_2 in ('proposed','confirmed','passed','timed_out')),
  created_at timestamptz not null default now()
);
create index if not exists matches_p1 on matches(person_1);
create index if not exists matches_p2 on matches(person_2);

create table if not exists checkins (
  match_id   uuid not null references matches(id) on delete cascade,
  person_id  uuid not null references people(id),
  self_at    timestamptz,                                   -- "I'm at the booth"
  partner_at timestamptz,                                   -- "my match showed up" (A only)
  primary key (match_id, person_id)
);

-- ---------- row-level security: phones read only their own rows ----------

alter table people   enable row level security;
alter table vendors  enable row level security;
alter table matches  enable row level security;
alter table checkins enable row level security;

grant select on people, vendors, matches, checkins to authenticated;   -- Supabase grants this by default; explicit here

create policy people_read_self   on people   for select to authenticated using (id = auth.uid());
create policy vendors_read_all   on vendors  for select to authenticated using (true);
create policy matches_read_own   on matches  for select to authenticated
  using (person_1 = auth.uid() or person_2 = auth.uid());
create policy checkins_read_own  on checkins for select to authenticated using (person_id = auth.uid());
-- No insert/update/delete policies: direct writes from phones are refused. Functions below bypass RLS.

-- ---------- helpers ----------

create or replace function _random_alias() returns text language sql volatile as $$
  select (array['Neon','Velvet','Copper','Lunar','Amber','Indigo','Mossy','Scarlet','Golden','Cobalt','Pearl','Ember'])[1 + floor(random()*12)]
      || ' '
      || (array['Otter','Heron','Lynx','Falcon','Fox','Badger','Ibis','Marten','Puffin','Stoat','Wren','Yak'])[1 + floor(random()*12)];
$$;

-- ---------- functions phones call (security definer = run with table-owner rights) ----------

-- 1. Join: create the caller's people row once. Variant alternates by sign-up order.
create or replace function join_event(p_name text default null)
returns people language plpgsql security definer set search_path = public as $$
declare me people;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into me from people where id = auth.uid();
  if found then return me; end if;
  insert into people (id, alias, name, variant)
  values (auth.uid(), _random_alias(), nullif(trim(p_name), ''), 'A')
  returning * into me;
  -- Everyone is variant A (pair at a booth) for the 2026-10-17 event. To run the A/B
  -- comparison instead, replace the line above's 'A' with a placeholder and add:
  --   update people set variant = case when me.seq % 2 = 1 then 'A' else 'B' end
  --     where id = me.id returning * into me;
  return me;
end $$;

-- 2. Find a match. Returns the caller's current match, a new one, or NULL if waiting (A only).
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

  -- longest-waiting A person I have never been matched with, in either slot
  select p.* into partner from people p
   where p.variant = 'A' and p.waiting_since is not null and p.id <> me.id
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
    return m;
  end if;

  update people set waiting_since = coalesce(waiting_since, now()) where id = me.id;
  return null;
end $$;

-- 3. Respond: confirm / pass / time out. Sets only the caller's own status column.
create or replace function respond_to_match(p_match uuid, p_action text)
returns matches language plpgsql security definer set search_path = public as $$
declare m matches;
begin
  if p_action not in ('confirmed','passed','timed_out') then raise exception 'bad action'; end if;
  select * into m from matches where id = p_match for update;
  if not found then raise exception 'no such match'; end if;
  if m.person_1 = auth.uid() then
    update matches set status_1 = p_action where id = p_match returning * into m;
  elsif m.person_2 = auth.uid() then
    update matches set status_2 = p_action where id = p_match returning * into m;
  else
    raise exception 'not your match';
  end if;
  return m;
end $$;

-- 4. Check in: 'self' = I'm at the booth; 'partner' = my match showed up (A only).
create or replace function check_in(p_match uuid, p_kind text)
returns checkins language plpgsql security definer set search_path = public as $$
declare m matches; c checkins;
begin
  if p_kind not in ('self','partner') then raise exception 'bad kind'; end if;
  select * into m from matches where id = p_match;
  if not found or (m.person_1 <> auth.uid() and m.person_2 <> auth.uid()) then raise exception 'not your match'; end if;
  if p_kind = 'partner' and m.person_2 is null then raise exception 'no partner in this match'; end if;
  insert into checkins (match_id, person_id) values (p_match, auth.uid()) on conflict do nothing;
  if p_kind = 'self' then
    update checkins set self_at = coalesce(self_at, now()) where match_id = p_match and person_id = auth.uid() returning * into c;
  else
    update checkins set partner_at = coalesce(partner_at, now()) where match_id = p_match and person_id = auth.uid() returning * into c;
  end if;
  return c;
end $$;

grant execute on function join_event(text), find_match(), respond_to_match(uuid,text), check_in(uuid,text) to authenticated;
revoke execute on function join_event(text), find_match(), respond_to_match(uuid,text), check_in(uuid,text) from anon, public;  -- signed-out callers get nothing, not even an error message
revoke execute on function _random_alias() from public;

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
  if partner_id is not null then
    select coalesce(nullif(trim(name), ''), alias) into partner_alias from people where id = partner_id;
  end if;
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


-- ---------- Saturday-night results (run as you, in the SQL editor) ----------
create or replace view results as
select
  p.variant,
  count(distinct m.id)                                                          as matches,
  count(distinct m.id) filter (where m.status_1 = 'confirmed' and (m.person_2 is null or m.status_2 = 'confirmed')) as confirmed,
  count(distinct c.match_id) filter (where c.self_at is not null)               as any_self_checkin,
  count(distinct c.match_id) filter (where c.partner_at is not null)            as any_partner_confirm
from people p
join matches m on m.person_1 = p.id
left join checkins c on c.match_id = m.id
group by p.variant;
