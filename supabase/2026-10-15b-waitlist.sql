-- Run once in the SQL editor. Waitlist for attendees, vendors, and organizers.
-- The page can add a sign-up but cannot read anyone's back.
create table if not exists waitlist (
  id         bigserial primary key,
  email      text not null check (position('@' in email) > 1 and length(email) <= 200),
  role       text not null check (role in ('organizer','vendor','attendee')),
  note       text check (note is null or length(note) <= 1000),
  source     text,                                   -- where they signed up: 'welcome' or 'after-match'
  person_id  uuid,                                   -- the anonymous app identity, if any
  created_at timestamptz not null default now()
);
alter table waitlist enable row level security;   -- no read policies: nobody can list it from the page

create or replace function join_waitlist(p_email text, p_role text, p_note text default null, p_source text default null)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_email is null or position('@' in trim(p_email)) < 2 then raise exception 'please enter a valid email'; end if;
  -- one sign-up per email + role; repeat submissions just update the note
  if exists (select 1 from waitlist where lower(email) = lower(trim(p_email)) and role = p_role) then
    update waitlist set note = coalesce(nullif(trim(p_note), ''), note) where lower(email) = lower(trim(p_email)) and role = p_role;
  else
    insert into waitlist (email, role, note, source, person_id)
    values (trim(p_email), p_role, nullif(trim(p_note), ''), p_source, auth.uid());
  end if;
end $fn$;
grant execute on function join_waitlist(text, text, text, text) to authenticated;
revoke execute on function join_waitlist(text, text, text, text) from anon, public;
