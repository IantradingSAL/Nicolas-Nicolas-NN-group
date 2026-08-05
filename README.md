# Nicolas Nicolas Group — Operations Console

A static, GitHub-Pages-hosted web console for the Nicolas Nicolas Group,
backed by Supabase. Fresh deployment — starts with no data.

## Pages

- `index.html` — landing / launcher, NN-branded
- `inventory.html` — items, quantities, reorder alerts
- `suppliers.html` — supplier directory + documents
- `roles.html` — role templates & permission matrix
- `employees.html` — team directory

All pages share a common Supabase client wired via `config.js` and a
small set of helper scripts (`auth_guard.js`, `access.js`, `lang.js`,
`table_sort.js`, `user_views.js`).

## Audit log — every user, every action

`audit_log.js` traces:

- page views (one row per page load)
- heartbeats every 30 s while a tab is open, so idle sessions are still recorded
- clicks on buttons / links / inputs, and form submissions
- every `insert` / `update` / `delete` / `upsert` on Supabase
- sign-in / sign-out events
- tab hide / show and page-close (best effort)

Rows go to `public.audit_log`. If Supabase isn't configured yet, events
queue in `localStorage` and flush automatically once real credentials are
plugged into `config.js`.

## Setup

1. Open `config.js` and replace the two placeholders with the URL and
   `anon` key from Supabase → Project Settings → API.
2. In Supabase, open the SQL editor and run `schema.sql` end to end.
3. In Supabase, open Storage and create a private bucket named
   `supplier-docs` (used by the Suppliers page for certifications and
   contracts). Add the storage policy from the bottom of `schema.sql`.
4. Commit and push — GitHub Pages serves the static site straight from
   `main`.

## Notes

- The included `auth_guard.js` and `access.js` are permissive stubs so
  the pages work with a fresh, empty deployment. Tighten them (and the
  RLS policies in `schema.sql`) before letting real users in.
- Placeholder Supabase config means the pages load, but any database
  call will fail with a network error until real credentials are set.
