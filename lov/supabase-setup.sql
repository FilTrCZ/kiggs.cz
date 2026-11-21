-- ============================================================================
-- Paw Trail (Kiggs × Pobar) — Supabase SQL Setup (účty hráčů + Google Sign-In)
-- ============================================================================
-- POSTUP NASTAVENÍ:
-- 1) V Supabase nech zapnuté registrace (Authentication -> Sign In / Providers -> Email -> Allow new users to sign up = ON),
--    protože hráči se mohou registrovat a přihlašovat přes Google nebo E-mail.
-- 2) Bezpečnost Velína smečky zajišťuje tabulka public.admin_users (pouze potvrzené
--    e-maily v ní mají admin oprávnění — nikdo jiný se do administrace nedostane!).
-- 3) Úplně dole v kroku 10 odkomentuj a doplň e-mail Kiggse (a případně Pobara)
--    do tabulky admin_users a klikni na RUN.
-- ============================================================================

-- 1. Globální nastavení hry (stav zamčeno / spuštěno)
create table if not exists public.app_settings (
    id integer primary key check (id = 1),
    trail_enabled boolean not null default false,
    teaser_message text not null default 'Paw Trail (Kiggs × Pobar) startuje už brzy 🐾',
    updated_at timestamptz not null default now()
);

insert into public.app_settings (id, trail_enabled, teaser_message)
values (1, false, 'Paw Trail (Kiggs × Pobar) startuje už brzy 🐾')
on conflict (id) do nothing;

-- 2. Whitelist povolených administrátorů (jen e-maily tady mají admin práva!)
create table if not exists public.admin_users (
    email text primary key,
    created_at timestamptz not null default now()
);

-- 3. Profily přihlášených hráčů (synchronizované napříč mobilem i PC)
create table if not exists public.profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    nickname text not null check (char_length(trim(nickname)) between 2 and 24),
    avatar_url text,
    updated_at timestamptz not null default now()
);

-- 4. Tabulka rozhleden (code_hash a secret_note jsou chráněné přes RLS)
create table if not exists public.spots (
    id text primary key,
    name text not null,
    region text not null,
    elevation integer not null default 0,
    lat double precision not null,
    lng double precision not null,
    hint text not null default '',
    secret_note text not null default '',
    code_hash text not null unique,
    created_at timestamptz not null default now()
);

-- 5. Tabulka nálezů hráčů (svázáno s auth.users.id -> 100% synchronizace mezi zařízeními)
create table if not exists public.claims (
    id bigint generated always as identity primary key,
    spot_id text not null references public.spots(id) on delete cascade,
    player_id text not null,
    nickname text not null check (char_length(trim(nickname)) between 2 and 24),
    gps_verified boolean not null default false,
    distance_m integer,
    is_ftf boolean not null default false,
    claimed_at timestamptz not null default now(),
    unique (spot_id, player_id)
);

create index if not exists idx_claims_spot on public.claims (spot_id, claimed_at asc);
create index if not exists idx_claims_player on public.claims (player_id);

-- 6. Zapnutí Row Level Security (vše jde výhradně přes zabezpečené RPC funkce)
alter table public.app_settings enable row level security;
alter table public.admin_users enable row level security;
alter table public.profiles enable row level security;
alter table public.spots enable row level security;
alter table public.claims enable row level security;

drop policy if exists "Block direct app_settings" on public.app_settings;
create policy "Block direct app_settings" on public.app_settings for all to anon, authenticated using (false) with check (false);

drop policy if exists "Block direct admin_users" on public.admin_users;
create policy "Block direct admin_users" on public.admin_users for all to anon, authenticated using (false) with check (false);

drop policy if exists "Block direct profiles" on public.profiles;
create policy "Block direct profiles" on public.profiles for all to anon, authenticated using (false) with check (false);

drop policy if exists "No direct spots select" on public.spots;
drop policy if exists "Block direct spots" on public.spots;
create policy "Block direct spots" on public.spots for all to anon, authenticated using (false) with check (false);

drop policy if exists "No direct claims write" on public.claims;
drop policy if exists "Block direct claims" on public.claims;
create policy "Block direct claims" on public.claims for all to anon, authenticated using (false) with check (false);

-- 7. Pomocné serverové funkce
-- Ověří, že je uživatel přihlášený, má potvrzený e-mail a je ve whitelistu admin_users
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public, auth
as $$
    select exists (
        select 1
        from public.admin_users a
        join auth.users u on lower(u.email) = lower(a.email)
        where u.id = auth.uid()
          and u.email_confirmed_at is not null
    );
$$;

-- Automaticky vytvoří/vrátí profil přihlášeného hráče (z Google jména nebo e-mailu)
create or replace function public.ensure_my_profile(p_preferred_nick text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_uid uuid := auth.uid();
    v_prof public.profiles%rowtype;
    v_user auth.users%rowtype;
    v_name text;
    v_avatar text;
begin
    if v_uid is null then
        return jsonb_build_object('ok', false, 'error', 'Nejsi přihlášený.');
    end if;

    select * into v_prof from public.profiles where user_id = v_uid;
    if found then
        return jsonb_build_object(
            'ok', true,
            'user_id', v_prof.user_id,
            'nickname', v_prof.nickname,
            'avatar_url', v_prof.avatar_url
        );
    end if;

    select * into v_user from auth.users where id = v_uid;
    v_avatar := coalesce(
        v_user.raw_user_meta_data ->> 'avatar_url',
        v_user.raw_user_meta_data ->> 'picture'
    );
    v_name := left(trim(coalesce(
        nullif(trim(coalesce(p_preferred_nick, '')), ''),
        nullif(trim(coalesce(v_user.raw_user_meta_data ->> 'nickname', '')), ''),
        nullif(trim(coalesce(v_user.raw_user_meta_data ->> 'full_name', '')), ''),
        nullif(trim(coalesce(v_user.raw_user_meta_data ->> 'name', '')), ''),
        split_part(coalesce(v_user.email, 'Stopar'), '@', 1)
    )), 24);

    if char_length(v_name) < 2 then
        v_name := 'Stopař';
    end if;

    insert into public.profiles (user_id, nickname, avatar_url)
    values (v_uid, v_name, v_avatar)
    on conflict (user_id) do update set
        avatar_url = coalesce(excluded.avatar_url, public.profiles.avatar_url)
    returning * into v_prof;

    return jsonb_build_object(
        'ok', true,
        'user_id', v_prof.user_id,
        'nickname', v_prof.nickname,
        'avatar_url', v_prof.avatar_url
    );
end;
$$;

-- Změna přezdívky hráče (propíše se i do jeho záznamů v žebříčku)
create or replace function public.update_my_profile(p_nickname text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_uid uuid := auth.uid();
    v_clean text := left(trim(coalesce(p_nickname, '')), 24);
begin
    if v_uid is null then
        return jsonb_build_object('ok', false, 'error', 'Nejsi přihlášený.');
    end if;
    if char_length(v_clean) < 2 then
        return jsonb_build_object('ok', false, 'error', 'Přezdívka musí mít alespoň 2 znaky.');
    end if;

    insert into public.profiles (user_id, nickname, updated_at)
    values (v_uid, v_clean, now())
    on conflict (user_id) do update set
        nickname = excluded.nickname,
        updated_at = now();

    update public.claims
    set nickname = v_clean
    where player_id = v_uid::text;

    return jsonb_build_object('ok', true, 'nickname', v_clean);
end;
$$;

-- ============================================================================
-- 8. VEŘEJNÉ A HRÁČSKÉ FUNKCE
-- ============================================================================

create or replace function public.get_trail_status()
returns jsonb
language sql
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'enabled', coalesce((select trail_enabled from public.app_settings where id = 1), false),
        'teaser_message', coalesce((select teaser_message from public.app_settings where id = 1), 'Paw Trail (Kiggs × Pobar) startuje už brzy 🐾'),
        'spots_count', (select count(*) from public.spots)
    );
$$;

drop function if exists public.get_public_spots(text);
create or replace function public.get_public_spots(p_player_id text default null)
returns table (
    id text,
    name text,
    region text,
    elevation integer,
    lat double precision,
    lng double precision,
    hint text,
    finders_count bigint,
    ftf_nickname text,
    ftf_at timestamptz,
    my_claimed boolean,
    my_gps_verified boolean,
    my_is_ftf boolean,
    my_claimed_at timestamptz,
    secret_note text
)
language sql
security definer
set search_path = public
as $$
    with me as (
        select coalesce(auth.uid()::text, p_player_id) as pid
    )
    select
        s.id,
        s.name,
        s.region,
        s.elevation,
        s.lat,
        s.lng,
        s.hint,
        coalesce(st.finders_count, 0) as finders_count,
        coalesce(ftf_p.nickname, ftf.nickname) as ftf_nickname,
        ftf.claimed_at as ftf_at,
        (mc.id is not null) as my_claimed,
        coalesce(mc.gps_verified, false) as my_gps_verified,
        coalesce(mc.is_ftf, false) as my_is_ftf,
        mc.claimed_at as my_claimed_at,
        case when mc.id is not null then s.secret_note else null end as secret_note
    from public.spots s
    cross join me
    left join (
        select spot_id, count(*) as finders_count
        from public.claims
        group by spot_id
    ) st on st.spot_id = s.id
    left join lateral (
        select c.player_id, c.nickname, c.claimed_at
        from public.claims c
        where c.spot_id = s.id and c.is_ftf = true
        order by c.claimed_at asc
        limit 1
    ) ftf on true
    left join public.profiles ftf_p on ftf_p.user_id::text = ftf.player_id
    left join public.claims mc
        on mc.spot_id = s.id
       and me.pid is not null
       and mc.player_id = me.pid
    where coalesce((select trail_enabled from public.app_settings where id = 1), false) = true
       or public.is_admin()
    order by s.created_at asc, s.name asc;
$$;

drop function if exists public.get_leaderboard(integer);
create or replace function public.get_leaderboard(p_limit integer default 30)
returns table (
    player_id text,
    nickname text,
    avatar_url text,
    spots_count bigint,
    gps_count bigint,
    ftf_count bigint,
    last_claim timestamptz
)
language sql
security definer
set search_path = public
as $$
    select
        c.player_id,
        coalesce(p.nickname, (array_agg(c.nickname order by c.claimed_at desc))[1]) as nickname,
        p.avatar_url,
        count(*) as spots_count,
        count(*) filter (where c.gps_verified) as gps_count,
        count(*) filter (where c.is_ftf) as ftf_count,
        max(c.claimed_at) as last_claim
    from public.claims c
    left join public.profiles p on p.user_id::text = c.player_id
    where coalesce((select trail_enabled from public.app_settings where id = 1), false) = true
       or public.is_admin()
    group by c.player_id, p.nickname, p.avatar_url
    order by spots_count desc, ftf_count desc, gps_count desc, last_claim asc
    limit greatest(1, least(p_limit, 100));
$$;

-- Odemčení rozhledny přihlášeným hráčem (server bere identitu přímo z auth.uid()!)
create or replace function public.claim_spot(
    p_code_hash text,
    p_player_id text default null,
    p_nickname text default null,
    p_lat double precision default null,
    p_lng double precision default null,
    p_radius_m integer default 300
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_uid uuid := auth.uid();
    v_enabled boolean;
    v_prof jsonb;
    v_clean_nick text;
    v_spot public.spots%rowtype;
    v_existing public.claims%rowtype;
    v_dist integer := null;
    v_gps_ok boolean := false;
    v_is_ftf boolean := false;
    v_dlat double precision;
    v_dlng double precision;
    v_a double precision;
begin
    if v_uid is null then
        return jsonb_build_object('ok', false, 'error', 'Pro zapsání rozhledny se prosím nejdřív přihlas (Google nebo e-mail).');
    end if;

    select trail_enabled into v_enabled from public.app_settings where id = 1;
    if not coalesce(v_enabled, false) and not public.is_admin() then
        return jsonb_build_object('ok', false, 'error', 'Paw Trail ještě není spuštěný — sleduj kiggs.cz!');
    end if;

    -- Zajisti profil (při prvním přihlášení se automaticky vezme jméno z Google účtu)
    v_prof := public.ensure_my_profile(p_nickname);
    v_clean_nick := coalesce(v_prof ->> 'nickname', 'Stopař');

    select * into v_spot
    from public.spots
    where code_hash = lower(trim(p_code_hash))
    limit 1;

    if not found then
        return jsonb_build_object('ok', false, 'error', 'Tento kód nepatří žádné známé rozhledně.');
    end if;

    if p_lat is not null and p_lng is not null then
        v_dlat := radians(p_lat - v_spot.lat);
        v_dlng := radians(p_lng - v_spot.lng);
        v_a := power(sin(v_dlat / 2), 2)
             + cos(radians(v_spot.lat)) * cos(radians(p_lat)) * power(sin(v_dlng / 2), 2);
        v_dist := round(6371000 * 2 * asin(least(1.0, sqrt(v_a))))::integer;
        v_gps_ok := (v_dist <= greatest(50, p_radius_m));
    end if;

    perform 1 from public.spots where id = v_spot.id for update;

    select * into v_existing
    from public.claims
    where spot_id = v_spot.id and player_id = v_uid::text;

    if found then
        if not v_existing.gps_verified and v_gps_ok then
            update public.claims
            set gps_verified = true, distance_m = v_dist, nickname = v_clean_nick
            where id = v_existing.id;
            return jsonb_build_object(
                'ok', true,
                'already_claimed', true,
                'upgraded_gps', true,
                'is_ftf', v_existing.is_ftf,
                'gps_verified', true,
                'distance_m', v_dist,
                'spot', jsonb_build_object(
                    'id', v_spot.id, 'name', v_spot.name, 'region', v_spot.region,
                    'elevation', v_spot.elevation, 'secret_note', v_spot.secret_note
                )
            );
        end if;

        return jsonb_build_object(
            'ok', true,
            'already_claimed', true,
            'upgraded_gps', false,
            'is_ftf', v_existing.is_ftf,
            'gps_verified', v_existing.gps_verified,
            'distance_m', v_dist,
            'spot', jsonb_build_object(
                'id', v_spot.id, 'name', v_spot.name, 'region', v_spot.region,
                'elevation', v_spot.elevation, 'secret_note', v_spot.secret_note
            )
        );
    end if;

    v_is_ftf := not exists (select 1 from public.claims where spot_id = v_spot.id);

    insert into public.claims (spot_id, player_id, nickname, gps_verified, distance_m, is_ftf)
    values (v_spot.id, v_uid::text, v_clean_nick, v_gps_ok, v_dist, v_is_ftf);

    return jsonb_build_object(
        'ok', true,
        'already_claimed', false,
        'upgraded_gps', false,
        'is_ftf', v_is_ftf,
        'gps_verified', v_gps_ok,
        'distance_m', v_dist,
        'spot', jsonb_build_object(
            'id', v_spot.id, 'name', v_spot.name, 'region', v_spot.region,
            'elevation', v_spot.elevation, 'secret_note', v_spot.secret_note
        )
    );
end;
$$;

-- ============================================================================
-- 9. ZABEZPEČENÉ ADMIN FUNKCE (jen pro přihlášené uživatele z admin_users!)
-- ============================================================================

create or replace function public.admin_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.is_admin() then
        return jsonb_build_object('ok', false, 'error', 'Tento účet nemá přístup do velína smečky.');
    end if;

    return jsonb_build_object(
        'ok', true,
        'email', auth.jwt() ->> 'email',
        'trail_enabled', coalesce((select trail_enabled from public.app_settings where id = 1), false),
        'teaser_message', coalesce((select teaser_message from public.app_settings where id = 1), ''),
        'spots_count', (select count(*) from public.spots),
        'claims_count', (select count(*) from public.claims)
    );
end;
$$;

create or replace function public.admin_set_trail_status(
    p_enabled boolean,
    p_teaser_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.is_admin() then
        raise exception 'Unauthorized';
    end if;

    update public.app_settings
    set trail_enabled = p_enabled,
        teaser_message = coalesce(nullif(trim(p_teaser_message), ''), teaser_message),
        updated_at = now()
    where id = 1;

    return jsonb_build_object(
        'ok', true,
        'trail_enabled', (select trail_enabled from public.app_settings where id = 1),
        'teaser_message', (select teaser_message from public.app_settings where id = 1)
    );
end;
$$;

drop function if exists public.admin_list_spots();
create or replace function public.admin_list_spots()
returns table (
    id text,
    name text,
    region text,
    elevation integer,
    lat double precision,
    lng double precision,
    hint text,
    secret_note text,
    finders_count bigint,
    ftf_nickname text,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.is_admin() then
        raise exception 'Unauthorized';
    end if;

    return query
    select
        s.id, s.name, s.region, s.elevation, s.lat, s.lng, s.hint, s.secret_note,
        coalesce(st.cnt, 0) as finders_count,
        coalesce(ftf_p.nickname, ftf.nickname) as ftf_nickname,
        s.created_at
    from public.spots s
    left join (select spot_id, count(*) as cnt from public.claims group by spot_id) st on st.spot_id = s.id
    left join lateral (
        select c.player_id, c.nickname from public.claims c where c.spot_id = s.id and c.is_ftf = true order by c.claimed_at asc limit 1
    ) ftf on true
    left join public.profiles ftf_p on ftf_p.user_id::text = ftf.player_id
    order by s.created_at desc;
end;
$$;

create or replace function public.admin_upsert_spot(
    p_id text,
    p_name text,
    p_region text,
    p_elevation integer,
    p_lat double precision,
    p_lng double precision,
    p_hint text,
    p_secret_note text,
    p_code_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.is_admin() then
        raise exception 'Unauthorized';
    end if;

    insert into public.spots (id, name, region, elevation, lat, lng, hint, secret_note, code_hash)
    values (
        lower(trim(p_id)), trim(p_name), trim(p_region), coalesce(p_elevation, 0),
        p_lat, p_lng, coalesce(trim(p_hint), ''), coalesce(trim(p_secret_note), ''), lower(trim(p_code_hash))
    )
    on conflict (id) do update set
        name = excluded.name,
        region = excluded.region,
        elevation = excluded.elevation,
        lat = excluded.lat,
        lng = excluded.lng,
        hint = excluded.hint,
        secret_note = excluded.secret_note,
        code_hash = excluded.code_hash;

    return jsonb_build_object('ok', true, 'id', lower(trim(p_id)));
end;
$$;

create or replace function public.admin_delete_spot(p_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.is_admin() then
        raise exception 'Unauthorized';
    end if;

    delete from public.spots where id = p_id;
    return jsonb_build_object('ok', true);
end;
$$;

drop function if exists public.admin_list_claims(integer);
create or replace function public.admin_list_claims(p_limit integer default 30)
returns table (
    id bigint,
    spot_id text,
    spot_name text,
    nickname text,
    gps_verified boolean,
    distance_m integer,
    is_ftf boolean,
    claimed_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.is_admin() then
        raise exception 'Unauthorized';
    end if;

    return query
    select c.id, c.spot_id, s.name as spot_name, coalesce(p.nickname, c.nickname) as nickname,
           c.gps_verified, c.distance_m, c.is_ftf, c.claimed_at
    from public.claims c
    join public.spots s on s.id = c.spot_id
    left join public.profiles p on p.user_id::text = c.player_id
    order by c.claimed_at desc
    limit greatest(1, least(p_limit, 100));
end;
$$;

create or replace function public.admin_delete_claim(p_claim_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.is_admin() then
        raise exception 'Unauthorized';
    end if;

    delete from public.claims where id = p_claim_id;
    return jsonb_build_object('ok', true);
end;
$$;

-- Oprávnění volání RPC
grant execute on function public.get_trail_status() to anon, authenticated;
grant execute on function public.get_public_spots(text) to anon, authenticated;
grant execute on function public.get_leaderboard(integer) to anon, authenticated;

grant execute on function public.ensure_my_profile(text) to authenticated;
grant execute on function public.update_my_profile(text) to authenticated;
grant execute on function public.claim_spot(text, text, text, double precision, double precision, integer) to authenticated;

grant execute on function public.admin_check() to authenticated;
grant execute on function public.admin_set_trail_status(boolean, text) to authenticated;
grant execute on function public.admin_list_spots() to authenticated;
grant execute on function public.admin_upsert_spot(text, text, text, integer, double precision, double precision, text, text, text) to authenticated;
grant execute on function public.admin_delete_spot(text) to authenticated;
grant execute on function public.admin_list_claims(integer) to authenticated;
grant execute on function public.admin_delete_claim(bigint) to authenticated;

-- ============================================================================
-- 10. PŘIDEJ SVŮJ (A POBARŮV) ADMIN E-MAIL! (Změň před spuštěním)
-- ============================================================================
-- insert into public.admin_users (email) values
-- ('tvuj-email@gmail.com'),
-- ('pobar-email@gmail.com')
-- on conflict (email) do nothing;
