-- Run once in the SQL editor. Adds last_seen so the pool count reflects who is searching right now,
-- while waiting_since keeps the longest-waiting order.
alter table people add column if not exists last_seen timestamptz;

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
    return m;
  end if;

  update people set waiting_since = coalesce(waiting_since, now()) where id = me.id;
  return null;
end $$;

create or replace function pool_size()
returns int language sql security definer set search_path = public stable as $fn$
  select count(*)::int from people where waiting_since is not null and last_seen > now() - interval '30 seconds'
$fn$;
