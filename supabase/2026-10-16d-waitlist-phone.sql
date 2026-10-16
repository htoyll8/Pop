-- Run once in the SQL editor (after 2026-10-15b-waitlist.sql).
-- The waitlist takes a phone number, an email, or both.
alter table waitlist add column if not exists phone text;
alter table waitlist alter column email drop not null;
alter table waitlist drop constraint if exists waitlist_email_check;
alter table waitlist drop constraint if exists waitlist_email_ok;
alter table waitlist add constraint waitlist_email_ok check (email is null or (position('@' in email) > 1 and length(email) <= 200));
alter table waitlist drop constraint if exists waitlist_phone_ok;
alter table waitlist add constraint waitlist_phone_ok check (phone is null or phone ~ '^\+?[0-9]{7,15}$');
alter table waitlist drop constraint if exists waitlist_contact;
alter table waitlist add constraint waitlist_contact check (email is not null or phone is not null);

drop function if exists join_waitlist(text, text, text, text);
create or replace function join_waitlist(p_email text default null, p_role text default 'attendee', p_note text default null,
                                         p_source text default null, p_phone text default null)
returns void language plpgsql security definer set search_path = public as $fn$
declare e text := nullif(lower(trim(p_email)), ''); ph text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), '');
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if e is null and ph is null then raise exception 'please add a phone number or an email'; end if;
  if e is not null and position('@' in e) < 2 then raise exception 'please enter a valid email'; end if;
  if ph is not null and ph !~ '^\+?[0-9]{7,15}$' then raise exception 'please enter a valid phone number'; end if;
  -- one sign-up per contact + role; a repeat just fills in what's new
  if exists (select 1 from waitlist where role = p_role and ((e is not null and lower(email) = e) or (ph is not null and phone = ph))) then
    update waitlist set email = coalesce(email, e), phone = coalesce(phone, ph), note = coalesce(nullif(trim(p_note), ''), note)
     where role = p_role and ((e is not null and lower(email) = e) or (ph is not null and phone = ph));
  else
    insert into waitlist (email, phone, role, note, source, person_id) values (e, ph, p_role, nullif(trim(p_note), ''), p_source, auth.uid());
  end if;
end $fn$;
grant execute on function join_waitlist(text, text, text, text, text) to authenticated;
revoke execute on function join_waitlist(text, text, text, text, text) from anon, public;
