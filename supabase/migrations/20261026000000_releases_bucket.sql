-- Public bucket for tester builds (APKs) shared by link before the app is on
-- Google Play. Read-only for everyone; uploads only through the dashboard or
-- CLI with the project owner's credentials (no insert/update policies).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'releases',
  'releases',
  true,
  209715200, -- 200 MB
  array['application/vnd.android.package-archive']
)
on conflict (id) do nothing;
