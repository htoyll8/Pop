-- Run once in the SQL editor (after 2026-10-16a-met-review.sql).
-- The review is now three faces plus an optional note, and both are optional
-- ("Match again" / "I'm done for now" save whatever was filled in).
alter table reviews alter column rating drop not null;
alter table reviews add column if not exists note text;

drop function if exists review_match(uuid, int, text[]);
create or replace function review_match(p_match uuid, p_rating int default null, p_tags text[] default '{}', p_note text default null)
returns void language plpgsql security definer set search_path = public as $fn$
declare m matches;
begin
  select * into m from matches where id = p_match;
  if not found or (m.person_1 <> auth.uid() and coalesce(m.person_2 <> auth.uid(), true)) then raise exception 'not your match'; end if;
  if p_rating is not null and p_rating not between 1 and 3 then raise exception 'rating must be 1, 2 or 3'; end if;
  insert into reviews (match_id, person_id, rating, tags, note) values (p_match, auth.uid(), p_rating, coalesce(p_tags, '{}'), nullif(trim(p_note), ''))
  on conflict (match_id, person_id) do update set rating = excluded.rating, tags = excluded.tags, note = excluded.note, created_at = now();
end $fn$;
grant execute on function review_match(uuid, int, text[], text) to authenticated;
