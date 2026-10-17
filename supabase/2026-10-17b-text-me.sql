-- Run once in the SQL editor (after 2026-10-17a-dashboard.sql).
-- "Text me when someone's looking": people leave a number while waiting; the dashboard lists them
-- with a one-tap text link (sent by hand from Tyler's phone), then marks them texted.
create table if not exists text_me (
  id         bigserial primary key,
  phone      text not null check (phone ~ '^\+[0-9]{10,15}$'),
  person_id  uuid default auth.uid(),
  created_at timestamptz not null default now(),
  texted_at  timestamptz
);
alter table text_me enable row level security;   -- no policies: phones write through request_text only

create or replace function request_text(p_phone text)
returns void language plpgsql security definer set search_path = public as $fn$
declare d text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if length(d) = 10 then d := '1' || d; end if;
  if length(d) < 11 or length(d) > 15 then raise exception 'That phone number doesn''t look right.'; end if;
  delete from text_me where person_id = auth.uid() and texted_at is null;   -- one pending request per person
  insert into text_me (phone) values ('+' || d);
end $fn$;
grant execute on function request_text(text) to authenticated;

create or replace function dash_texted(p_key text, p_id bigint)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if p_key is null or not exists (select 1 from dash_keys where key = p_key) then raise exception 'bad key'; end if;
  update text_me set texted_at = now() where id = p_id and texted_at is null;
end $fn$;
grant execute on function dash_texted(text, bigint) to anon, authenticated;

create or replace function dash_text_list(p_key text)
returns jsonb language plpgsql security definer set search_path = public stable as $fn$
begin
  if p_key is null or not exists (select 1 from dash_keys where key = p_key) then raise exception 'bad key'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'phone', t.phone, 'at', t.created_at,
            'name', coalesce(nullif(trim(p.name), ''), p.alias)) order by t.created_at)
         from text_me t left join people p on p.id = t.person_id where t.texted_at is null), '[]');
end $fn$;
grant execute on function dash_text_list(text) to anon, authenticated;
