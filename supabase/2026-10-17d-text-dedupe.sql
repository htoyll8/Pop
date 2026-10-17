-- Run once in the SQL editor (after 2026-10-17c-text-queue.sql).
-- One spot in the text queue per phone number: asking again (from any phone or browser) replaces the old request.
create or replace function request_text(p_phone text)
returns void language plpgsql security definer set search_path = public as $fn$
declare d text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if length(d) = 10 then d := '1' || d; end if;
  if length(d) < 11 or length(d) > 15 then raise exception 'That phone number doesn''t look right.'; end if;
  delete from text_me where (person_id = auth.uid() or phone = '+' || d) and texted_at is null and match_id is null;
  insert into text_me (phone) values ('+' || d);
end $fn$;
