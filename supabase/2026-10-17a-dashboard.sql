-- Run once in the SQL editor. Powers dash.html (live event dashboard).
-- The dashboard needs a private key; add it separately (not in this file, the repo is public):
--   insert into dash_keys (key) values ('<your key>');
create table if not exists dash_keys (key text primary key);
alter table dash_keys enable row level security;   -- no policies: only event_dashboard reads it

create or replace function event_dashboard(p_key text)
returns jsonb language plpgsql security definer set search_path = public stable as $fn$
begin
  if p_key is null or not exists (select 1 from dash_keys where key = p_key) then raise exception 'bad key'; end if;
  return jsonb_build_object(
    'now', now(),
    'people', (select count(*) from people),
    'here_now', (select count(*) from people where last_seen > now() - interval '2 minutes'),
    'searching', (select count(*) from people where waiting_since is not null and last_seen > now() - interval '30 seconds'),
    'matches', (select count(*) from matches),
    'its_on', (select count(*) from matches where status_1 = 'confirmed' and status_2 = 'confirmed'),
    'declined', (select count(*) from matches where 'passed' in (status_1, status_2)),
    'timed_out', (select count(*) from matches where 'timed_out' in (status_1, status_2)),
    'met', (select count(*) from matches m where m.met_at is not null
              or (select count(*) from checkins c where c.match_id = m.id and c.self_at is not null) = 2),
    'reviews', (select jsonb_build_object(
        'n', count(*), 'meh', count(*) filter (where rating = 1), 'good', count(*) filter (where rating = 2),
        'amazing', count(*) filter (where rating = 3), 'no_show', count(*) filter (where 'no_show' = any(tags))) from reviews),
    'waitlist', (select count(*) from waitlist),
    'reports_hour', (select count(*) from reports where created_at > now() - interval '1 hour'),
    'per_spot', coalesce((select jsonb_agg(x order by x->>'n' desc) from (
        select jsonb_build_object('name', v.name, 'n', count(m.id)) x from vendors v join matches m on m.vendor_id = v.id group by v.name) s), '[]'),
    'recent', coalesce((select jsonb_agg(r order by r->>'at' desc) from (
        select jsonb_build_object(
          'at', m.created_at,
          'a', coalesce(nullif(trim(p1.name), ''), p1.alias), 'b', coalesce(nullif(trim(p2.name), ''), p2.alias),
          'spot', v.name, 's1', m.status_1, 's2', m.status_2,
          'here', (select count(*) from checkins c where c.match_id = m.id and c.self_at is not null),
          'met', m.met_at is not null,
          'ratings', (select jsonb_agg(case when 'no_show' = any(rv.tags) then 0 else rv.rating end) from reviews rv where rv.match_id = m.id)) r
        from matches m join people p1 on p1.id = m.person_1 left join people p2 on p2.id = m.person_2 join vendors v on v.id = m.vendor_id
        order by m.created_at desc limit 25) s), '[]'),
    'notes', coalesce((select jsonb_agg(jsonb_build_object('at', created_at, 'rating', rating, 'note', note) order by created_at desc)
        from (select * from reviews where note is not null order by created_at desc limit 15) s), '[]'),
    'reports', coalesce((select jsonb_agg(jsonb_build_object('at', created_at, 'kind', kind, 'msg', left(message, 200), 'v', app_version) order by created_at desc)
        from (select * from reports order by created_at desc limit 10) s), '[]')
  );
end $fn$;
grant execute on function event_dashboard(text) to anon, authenticated;
