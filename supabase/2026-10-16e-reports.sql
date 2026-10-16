-- Run once in the SQL editor.
-- Bug reports: automatic error reports from the page, plus "Report a bug" from people.
-- The page can send a report but cannot read any back; read them in the Table Editor.
create table if not exists reports (
  id          bigserial primary key,
  kind        text not null check (kind in ('auto', 'user')),
  message     text not null check (length(message) <= 2000),
  detail      jsonb,                                  -- phone/browser, screen size, which screen, etc.
  app_version text,
  person_id   uuid,
  created_at  timestamptz not null default now()
);
alter table reports enable row level security;   -- no read policies

create or replace function report_issue(p_kind text, p_message text, p_detail jsonb default null, p_version text default null)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_kind not in ('auto', 'user') or coalesce(trim(p_message), '') = '' then return; end if;
  -- keep a broken phone from flooding the table: at most 40 reports per person per hour
  if (select count(*) from reports where person_id = auth.uid() and created_at > now() - interval '1 hour') >= 40 then return; end if;
  insert into reports (kind, message, detail, app_version, person_id) values (p_kind, left(trim(p_message), 2000), p_detail, p_version, auth.uid());
end $fn$;
grant execute on function report_issue(text, text, jsonb, text) to authenticated;
revoke execute on function report_issue(text, text, jsonb, text) from anon, public;
