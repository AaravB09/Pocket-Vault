-- AI access is authenticated, rate-limited, and auditable. Apply with:
--   supabase db push

create table if not exists public.ai_usage_windows (
  user_id uuid not null references auth.users(id) on delete cascade,
  window_started_at timestamptz not null,
  request_count integer not null default 0 check (request_count >= 0),
  primary key (user_id, window_started_at)
);

alter table public.ai_usage_windows enable row level security;
-- This table is deliberately inaccessible to application clients. Only the
-- Edge Function's service-role client calls the RPC below.

create or replace function public.consume_ai_quota(
  p_user_id uuid,
  p_limit integer default 20,
  p_window_seconds integer default 3600
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_window timestamptz;
  v_count integer;
begin
  if p_limit < 1 or p_limit > 1000 or p_window_seconds < 60 or p_window_seconds > 86400 then
    raise exception 'invalid quota parameters';
  end if;

  v_window := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);

  insert into public.ai_usage_windows (user_id, window_started_at, request_count)
  values (p_user_id, v_window, 1)
  on conflict (user_id, window_started_at)
  do update set request_count = public.ai_usage_windows.request_count + 1
  returning request_count into v_count;

  return v_count <= p_limit;
end;
$$;

revoke all on function public.consume_ai_quota(uuid, integer, integer) from public;
grant execute on function public.consume_ai_quota(uuid, integer, integer) to service_role;

-- Retain only a short audit window. Schedule this statement daily with
-- Supabase Cron/pg_cron: delete from public.ai_usage_windows where
-- window_started_at < now() - interval '3 days';
