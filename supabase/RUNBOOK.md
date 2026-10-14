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
5. **Copy two keys** from Project Settings → API: the **Project URL** and the **anon public key** go in the page. The **service_role key** stays on your laptop, never in the page.
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
7. **Saturday night:** `select * from results;` and the raw tables, in the SQL editor.

## What the page will call (next step)
`supabase.auth.signInAnonymously()` once → `rpc('join_event', {p_name})` → `rpc('find_match')` every 3 s until non-null → show card → `rpc('respond_to_match', ...)` → `rpc('check_in', ...)`.
