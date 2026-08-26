-- ============================================================================
--  DHRUVO SANGSAD (ধ্রুব সংসদ) — Supabase setup.sql
-- ----------------------------------------------------------------------------
--  KOTOBAW RUN KORBEN (কোথায় রান করবেন):
--    Supabase Dashboard -> SQL Editor -> "New query" -> paste -> Run
--  EITA IDEMPOTENT — dui bar onek bar run korleo safe (re-run safe).
--  Table thakle missing column thik korbe, RLS policy shuru theke banabe.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) HELPER FUNCTIONS
--    (SECURITY DEFINER must be — otherwise RLS-on-profiles recursion happens)
-- ----------------------------------------------------------------------------
create or replace function public.current_role()
returns text
language sql stable security definer set search_path = public
as $$
  select role from public.profiles where uid = auth.uid() limit 1
$$;

create or replace function public.is_staff()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.current_role() in ('ADMIN','MAKER'), false)
$$;

create or replace function public.current_member_id()
returns text
language sql stable security definer set search_path = public
as $$
  select member_id from public.profiles where uid = auth.uid() limit 1
$$;

create or replace function public.current_username()
returns text
language sql stable security definer set search_path = public
as $$
  select username from public.profiles where uid = auth.uid() limit 1
$$;

-- ----------------------------------------------------------------------------
-- 2) TABLES (exact schema the app writes to; created only if missing)
--    NOTE: app stores all timestamps as epoch MILLISECONDS (bigint)
-- ----------------------------------------------------------------------------
create table if not exists public.profiles (
  uid          uuid,
  id           uuid not null default gen_random_uuid() primary key,
  role         text not null default 'MEMBER',
  member_id    text,
  username     text,
  display_name text,
  created_at   bigint,
  updated_at   bigint
);

create table if not exists public.members (
  id                  text primary key,
  member_id           text,
  name_bn             text,
  name_en             text,
  father_bn           text,
  father_en           text,
  mother_bn           text,
  mother_en           text,
  mobile              text,
  whatsapp            text,
  email               text,
  nid                 text,
  dob                 text,
  profession          text,
  address             text,
  monthly_installment numeric,
  status              text,
  type                text,
  username            text,
  auth_uid            text,
  created_at          bigint,
  updated_at          bigint
);

create table if not exists public.deposits (
  id              text primary key,
  member_id       text,
  member_name     text,
  date            text,
  deposit_date    date,
  type            text,
  description     text,
  amount          numeric,
  payment_method  text,
  payment_detail  text,
  cash_depositor  text,
  bank_method     text,
  mobile_method   text,
  reference       text,
  note            text,
  submitted_by    text,
  submitted_at    bigint,
  status          text,
  reviewed_by     text,
  reviewed_at     bigint,
  created_at      bigint,
  updated_at      bigint
);

create table if not exists public.notifications (
  id         text primary key,
  message    text,
  audience   text,
  type       text,
  member_id  text,
  deposit_id text,
  created_at bigint,
  updated_at bigint
);

create table if not exists public.activity_logs (
  id         text primary key,
  "user"     text,
  role       text,
  action     text,
  details    text,
  date       text,
  time       text,
  created_at bigint,
  updated_at bigint
);

create table if not exists public.settings (
  id         text primary key,
  key        text,
  value      text,
  updated_at bigint
);

-- ----------------------------------------------------------------------------
-- 3) ENSURE ALL COLUMNS EXIST (fills gaps in pre-existing tables)
-- ----------------------------------------------------------------------------
do $$
declare
  t  text;
  c  text;
  ty text;
  cols text[][] := array[
    -- profiles
    ['profiles','uid','uuid'],
    ['profiles','id','uuid'],
    ['profiles','role','text'],
    ['profiles','member_id','text'],
    ['profiles','username','text'],
    ['profiles','display_name','text'],
    ['profiles','created_at','bigint'],
    ['profiles','updated_at','bigint'],
    -- members
    ['members','id','text'],
    ['members','member_id','text'],
    ['members','name_bn','text'],
    ['members','name_en','text'],
    ['members','father_bn','text'],
    ['members','father_en','text'],
    ['members','mother_bn','text'],
    ['members','mother_en','text'],
    ['members','mobile','text'],
    ['members','whatsapp','text'],
    ['members','email','text'],
    ['members','nid','text'],
    ['members','dob','text'],
    ['members','profession','text'],
    ['members','address','text'],
    ['members','monthly_installment','numeric'],
    ['members','status','text'],
    ['members','type','text'],
    ['members','username','text'],
    ['members','auth_uid','text'],
    ['members','created_at','bigint'],
    ['members','updated_at','bigint'],
    -- deposits
    ['deposits','id','text'],
    ['deposits','member_id','text'],
    ['deposits','member_name','text'],
    ['deposits','date','text'],
    ['deposits','deposit_date','date'],
    ['deposits','type','text'],
    ['deposits','description','text'],
    ['deposits','amount','numeric'],
    ['deposits','payment_method','text'],
    ['deposits','payment_detail','text'],
    ['deposits','cash_depositor','text'],
    ['deposits','bank_method','text'],
    ['deposits','mobile_method','text'],
    ['deposits','reference','text'],
    ['deposits','note','text'],
    ['deposits','submitted_by','text'],
    ['deposits','submitted_at','bigint'],
    ['deposits','status','text'],
    ['deposits','reviewed_by','text'],
    ['deposits','reviewed_at','bigint'],
    ['deposits','created_at','bigint'],
    ['deposits','updated_at','bigint'],
    -- notifications
    ['notifications','id','text'],
    ['notifications','message','text'],
    ['notifications','audience','text'],
    ['notifications','type','text'],
    ['notifications','member_id','text'],
    ['notifications','deposit_id','text'],
    ['notifications','created_at','bigint'],
    ['notifications','updated_at','bigint'],
    -- activity_logs
    ['activity_logs','id','text'],
    ['activity_logs','user','text'],
    ['activity_logs','role','text'],
    ['activity_logs','action','text'],
    ['activity_logs','details','text'],
    ['activity_logs','date','text'],
    ['activity_logs','time','text'],
    ['activity_logs','created_at','bigint'],
    ['activity_logs','updated_at','bigint'],
    -- settings
    ['settings','id','text'],
    ['settings','key','text'],
    ['settings','value','text'],
    ['settings','updated_at','bigint']
  ];
begin
  foreach t, c, ty slice 1 in array cols loop
    execute format('alter table public.%I add column if not exists %I %s', t, c, ty);
  end loop;
end
$$;

-- ----------------------------------------------------------------------------
-- 4) NORMALIZE TYPES IF A PRE-EXISTING TABLE USED DIFFERENT ONES
--    timestamp columns  -> bigint (epoch ms)   [data preserved]
--    members.auth_uuid  -> text (if uuid)
-- ----------------------------------------------------------------------------
do $$
declare
  r   record;
  cur text;
  ts_cols text[][] := array[
    ['members','created_at'],
    ['members','updated_at'],
    ['deposits','submitted_at'],
    ['deposits','reviewed_at'],
    ['deposits','created_at'],
    ['deposits','updated_at'],
    ['notifications','created_at'],
    ['notifications','updated_at'],
    ['activity_logs','created_at'],
    ['activity_logs','updated_at'],
    ['settings','updated_at'],
    ['profiles','created_at'],
    ['profiles','updated_at']
  ];
begin
  foreach r slice 1 in array ts_cols loop
    begin
      select format_type(atttypid, atttypmod) into cur
      from pg_attribute
      where attrelid = ('public.' || r[1])::regclass and attname = r[2];
      if cur in ('timestamp with time zone', 'timestamp without time zone') then
        execute format(
          'alter table public.%1$I alter column %2$I type bigint using (date_part(''epoch'', %2$I)::bigint * 1000)',
          r[1], r[2]);
      end if;
    exception when undefined_column then
      null;
    end;
  end loop;
end
$$;

do $$
declare cur text;
begin
  select format_type(atttypid, atttypmod) into cur
  from pg_attribute
  where attrelid = 'public.members'::regclass and attname = 'auth_uid';
  if cur = 'uuid' then
    alter table public.members alter column auth_uid type text using auth_uid::text;
  end if;
exception when undefined_column then
  null;
end
$$;

-- profiles.id needs a default so the app's {uid, ...} insert always works
do $$
begin
  if not exists (
    select 1
    from pg_attrdef a
    join pg_attribute at on at.attrelid = a.adrelid and at.attnum = a.adnum
    where at.attrelid = 'public.profiles'::regclass and at.attname = 'id'
  ) then
    alter table public.profiles alter column id set default gen_random_uuid();
  end if;
exception when undefined_column then
  null;
end
$$;

-- ----------------------------------------------------------------------------
-- 5) PRIMARY KEYS (upsert onConflict:"id" needs a unique key on id)
-- ----------------------------------------------------------------------------
do $$
declare
  t      text;
  has_pk boolean;
  tbls   text[] := array['profiles','members','deposits','notifications','activity_logs','settings'];
begin
  foreach t in array tbls loop
    select count(*) > 0 into has_pk
    from pg_constraint c
    where c.conrelid = ('public.' || t)::regclass and c.contype = 'p';
    if not has_pk then
      begin
        execute format('alter table public.%I add primary key (id)', t);
      exception when duplicate_key then
        raise notice '%(id) has duplicate values — primary key skipped (dedupe manually)', t;
      end;
    end if;
  end loop;
end
$$;

-- ----------------------------------------------------------------------------
-- 6) INDEXES (used by the app's queries)
-- ----------------------------------------------------------------------------
create index if not exists members_member_id_idx  on public.members(member_id);
create index if not exists members_mobile_idx     on public.members(mobile);
create index if not exists members_username_idx   on public.members(username);
create index if not exists members_auth_uid_idx   on public.members(auth_uid);
create index if not exists deposits_member_id_idx on public.deposits(member_id);
create index if not exists deposits_date_idx      on public.deposits(deposit_date);
create index if not exists deposits_status_idx    on public.deposits(status);
create index if not exists notifications_member_id_idx on public.notifications(member_id);
create index if not exists notifications_audience_idx  on public.notifications(audience);
create index if not exists activity_logs_user_idx      on public.activity_logs("user");
create index if not exists settings_key_idx            on public.settings(key);
create index if not exists profiles_uid_idx            on public.profiles(uid);

-- ----------------------------------------------------------------------------
-- 7) ROW LEVEL SECURITY — the part that was missing
-- ----------------------------------------------------------------------------
alter table public.profiles      enable row level security;
alter table public.members       enable row level security;
alter table public.deposits      enable row level security;
alter table public.notifications enable row level security;
alter table public.activity_logs enable row level security;
alter table public.settings      enable row level security;

-- Start from a clean slate: remove ALL pre-existing policies so only the
-- policies below apply (policies are OR-joined, stale ones would leak).
do $$
declare
  p   record;
  t   text;
  tbls text[] := array['profiles','members','deposits','notifications','activity_logs','settings'];
begin
  foreach t in array tbls loop
    for p in
      select polname from pg_policy where polrelid = ('public.' || t)::regclass
    loop
      execute format('drop policy %I on public.%I', p.polname, t);
    end loop;
  end loop;
end
$$;

-- profiles: each user manages their own row
create policy "profiles_select_own" on public.profiles for select
  using (uid = auth.uid() or id = auth.uid());

create policy "profiles_insert_own" on public.profiles for insert
  with check (uid = auth.uid() or id = auth.uid());

create policy "profiles_update_own" on public.profiles for update
  using (uid = auth.uid() or id = auth.uid())
  with check (uid = auth.uid() or id = auth.uid());

-- members:
--  * SELECT is open — the app logs members in through ANON lookups by
--    member_id/mobile BEFORE authentication (publishable key is public anyway).
--  * Anonymous registration inserts only work with status 'pending'
--    (staff approve later). Everything else: staff full access, member own row.
create policy "members_select_all" on public.members for select
  using (true);

create policy "members_insert_pending_or_staff" on public.members for insert
  with check (public.is_staff() or status = 'pending');

create policy "members_update_staff_or_own" on public.members for update
  using (public.is_staff() or auth_uid = auth.uid()::text or member_id = public.current_member_id())
  with check (public.is_staff() or auth_uid = auth.uid()::text or member_id = public.current_member_id());

create policy "members_delete_staff" on public.members for delete
  using (public.is_staff());

-- deposits: staff everything, member only their own rows
create policy "deposits_select_staff_or_own" on public.deposits for select
  using (public.is_staff() or member_id = public.current_member_id());

create policy "deposits_insert_staff_or_own" on public.deposits for insert
  with check (public.is_staff() or member_id = public.current_member_id());

create policy "deposits_update_staff_or_own" on public.deposits for update
  using (public.is_staff() or member_id = public.current_member_id())
  with check (public.is_staff() or member_id = public.current_member_id());

create policy "deposits_delete_staff" on public.deposits for delete
  using (public.is_staff());

-- notifications: staff sees all; members see only their own member-audience rows
create policy "notifications_select_staff_or_own" on public.notifications for select
  using (public.is_staff() or (audience = 'member' and member_id = public.current_member_id()));

-- anon insert allowed (the registration screen creates a staff notification
-- before any login — same design as members above)
create policy "notifications_insert_all" on public.notifications for insert
  with check (true);

create policy "notifications_update_staff_or_own" on public.notifications for update
  using (public.is_staff() or (audience = 'member' and member_id = public.current_member_id()));

create policy "notifications_delete_staff" on public.notifications for delete
  using (public.is_staff());

-- activity logs: staff all, members their own entries
create policy "activity_logs_select_staff_or_own" on public.activity_logs for select
  using (public.is_staff() or "user" = public.current_member_id() or "user" = public.current_username());

create policy "activity_logs_insert_authed" on public.activity_logs for insert
  with check (auth.uid() is not null);

create policy "activity_logs_update_staff" on public.activity_logs for update
  using (public.is_staff());

-- settings: staff only (cloudCheck uses anon and is fine with a 403)
create policy "settings_select_staff" on public.settings for select
  using (public.is_staff());

create policy "settings_insert_staff" on public.settings for insert
  with check (public.is_staff());

create policy "settings_update_staff" on public.settings for update
  using (public.is_staff())
  with check (public.is_staff());

create policy "settings_delete_staff" on public.settings for delete
  using (public.is_staff());

-- ----------------------------------------------------------------------------
-- 8) REALTIME — publish tables for postgres_changes (skipped silently if the
--    publication does not exist or tables are already added)
-- ----------------------------------------------------------------------------
do $$
begin
  alter publication supabase_realtime add table public.members;
exception when others then
  raise notice 'realtime(members): %', sqlerrm;
end
$$;
do $$
begin
  alter publication supabase_realtime add table public.deposits;
exception when others then
  raise notice 'realtime(deposits): %', sqlerrm;
end
$$;
do $$
begin
  alter publication supabase_realtime add table public.notifications;
exception when others then
  raise notice 'realtime(notifications): %', sqlerrm;
end
$$;
do $$
begin
  alter publication supabase_realtime add table public.activity_logs;
exception when others then
  raise notice 'realtime(activity_logs): %', sqlerrm;
end
$$;
do $$
begin
  alter publication supabase_realtime add table public.settings;
exception when others then
  raise notice 'realtime(settings): %', sqlerrm;
end
$$;
do $$
begin
  alter publication supabase_realtime add table public.profiles;
exception when others then
  raise notice 'realtime(profiles): %', sqlerrm;
end
$$;

-- ============================================================================
-- DONE. Refresh the app — it will show "Cloud Online" and sync automatically.
-- ============================================================================
