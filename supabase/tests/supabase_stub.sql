-- Just enough of Supabase for the migrations to run on plain Postgres:
-- its roles, auth.users, storage.buckets, and its default grants.
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
end $$;
alter role service_role bypassrls;
create schema auth;
create table auth.users (id uuid primary key);
create schema storage;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
grant usage on schema public to anon, authenticated, service_role;
-- Supabase grants everything on public tables/functions to these roles by
-- default and relies on RLS + explicit revokes.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
