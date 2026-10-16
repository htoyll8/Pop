-- Run once in the SQL editor.
-- "We met!": a match can be marked as met (by tapping the button, or by scanning the other person's face QR),
-- and each person can leave a quick review (1 = meh, 2 = good, 3 = amazing, plus optional tags).

alter table matches add column if not exists met_at timestamptz;

create table if not exists reviews (
  match_id   uuid not null references matches(id) on delete cascade,
  person_id  uuid not null references people(id) on delete cascade default auth.uid(),
  rating     smallint not null check (rating between 1 and 3),
  tags       text[] not null default '{}',
  created_at timestamptz not null default now(),
  primary key (match_id, person_id)
);
alter table reviews enable row level security;   -- no read policies: phones write through review_match only

-- either person in the match marks it met; the first time wins
create or replace function confirm_met(p_match uuid)
returns timestamptz language plpgsql security definer set search_path = public as $fn$
declare m matches;
begin
  select * into m from matches where id = p_match;
  if not found or (m.person_1 <> auth.uid() and coalesce(m.person_2 <> auth.uid(), true)) then raise exception 'not your match'; end if;
  update matches set met_at = coalesce(met_at, now()) where id = p_match returning * into m;
  return m.met_at;
end $fn$;

create or replace function review_match(p_match uuid, p_rating int, p_tags text[] default '{}')
returns void language plpgsql security definer set search_path = public as $fn$
declare m matches;
begin
  select * into m from matches where id = p_match;
  if not found or (m.person_1 <> auth.uid() and coalesce(m.person_2 <> auth.uid(), true)) then raise exception 'not your match'; end if;
  insert into reviews (match_id, person_id, rating, tags) values (p_match, auth.uid(), p_rating, coalesce(p_tags, '{}'))
  on conflict (match_id, person_id) do update set rating = excluded.rating, tags = excluded.tags, created_at = now();
end $fn$;

-- the card now also says when the match was marked met
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
    'met_at', m.met_at,
    'created_at', m.created_at);
end $fn$;

grant execute on function confirm_met(uuid) to authenticated;
grant execute on function review_match(uuid, int, text[]) to authenticated;
