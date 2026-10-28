-- iPhone: App Attest keys, and Sign in with Apple tokens for revocation.
--
-- App Attest (iPhone): one row per key the genuine app registered. The
-- public key verifies each call's assertion; sign_count only ever goes up,
-- so a captured assertion can't be replayed.
--
-- Keys belong to an install on a device, not to a person: user_id records
-- who registered it (for the per-user registration cap) and is cleared when
-- that account is deleted.

create table if not exists public.app_attest_keys (
  key_id text primary key check (key_id ~ '^[A-Za-z0-9_-]{43}$'),
  public_key bytea not null check (octet_length(public_key) = 65),
  sign_count bigint not null default 0 check (sign_count >= 0),
  environment text not null check (environment in ('production', 'development')),
  user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);

create index if not exists app_attest_keys_user_recent
  on public.app_attest_keys (user_id, created_at);

-- Only the Edge Functions (service role) touch this table.
alter table public.app_attest_keys enable row level security;
revoke all on public.app_attest_keys from anon, authenticated;

-- Sign in with Apple: the refresh token Apple issued for each account that
-- signed in with Apple. Kept only so that deleting the account can revoke
-- ClearSkin's access at Apple, as Apple requires; deleted with the account.
create table if not exists public.apple_tokens (
  user_id uuid primary key references auth.users (id) on delete cascade,
  refresh_token text not null check (length(refresh_token) between 1 and 2000),
  updated_at timestamptz not null default now()
);

alter table public.apple_tokens enable row level security;
revoke all on public.apple_tokens from anon, authenticated;
