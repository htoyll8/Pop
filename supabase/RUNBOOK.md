# Supabase setup for Saturday (do today; free projects pause after a week idle)

1. **Create the project.** supabase.com → New project → name `crosspaths`, region US East, generate a DB password and keep it. Wait ~2 min.
2. **Enable anonymous sign-in.** Authentication → Sign In / Providers → Anonymous sign-ins → ON. (This is how a phone gets an identity that policies can trust: `auth.uid()`.)
3. **Run the schema.** SQL Editor → New query → paste all of `schema.sql` → Run. Expect "Success. No rows returned."
4. **Type in the vendors.** SQL Editor:
   ```sql
   insert into vendors (name, location) values
     ('Mango Cart', 'north tent, by the entrance'),
     ('Vendor Two', 'left of the stage');
   ```
   The `location` text is what the rendezvous card shows; write it the way you'd say it out loud.
5. **Copy two values.** Settings → Data API shows the **Project URL** (`https://<ref>.supabase.co`). Settings → API Keys shows the **publishable key** (`sb_publishable_...`, formerly called the anon key); both go in the page. The **secret key** (`sb_secret_...`, formerly service_role) stays on your laptop, never in the page.
6. **Smoke test in the SQL editor** (simulates two phones; the editor runs as the owner, so we set the uid by hand):
   ```sql
   -- phone 1 joins and searches (variant A, first sign-up)
   select set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
   insert into auth.users (id) values (current_setting('request.jwt.claim.sub')::uuid);
   select * from join_event('Tyler');
   select * from find_match();          -- NULL: waiting
   ```
   Run again in a new query with a second uuid; the second person is variant B and gets a vendor immediately. A third (variant A) pairs with the first. Then:
   ```sql
   select * from respond_to_match('<match id>', 'confirmed');
   select * from check_in('<match id>', 'self');
   select * from results;
   ```
7. **If the schema was already run before 10/14 14:10:** run this once in the SQL editor:
   ```sql
   revoke execute on function join_event(text), find_match(), respond_to_match(uuid,text), check_in(uuid,text) from anon, public;
   ```
8. **Saturday night:** `select * from results;` and the raw tables, in the SQL editor.

## Verified against the live project (2026-10-14)
Anonymous sign-in, join_event (variants alternate), find_match (A pool + pairing across clients, B instant, vendor rotation, same match on re-search), respond_to_match (own column only; foreign match refused), check_in (self + partner), RLS (own rows only). Tested with curl from a laptop, four to seven anonymous phones.

**API detail for the page:** when `find_match` returns NULL (waiting), PostgREST sends an object with every field null, not a bare `null`. Check `result.id == null` for "waiting".

## What the page will call (next step)
`supabase.auth.signInAnonymously()` once → `rpc('join_event', {p_name})` → `rpc('find_match')` every 3 s until non-null → show card → `rpc('respond_to_match', ...)` → `rpc('check_in', ...)`.

## Demo / event-day reset
```sql
truncate checkins, matches, people;   -- keeps vendors and the schema; phones re-join on next tap
```
Variant: everyone is A for the 10/17 event (see join_event in schema.sql for how to restore A/B alternation).
