CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name text NOT NULL CHECK (octet_length(display_name) BETWEEN 1 AND 120),
  username text NOT NULL UNIQUE CHECK (username ~ '^[A-Za-z0-9_]{3,32}$'),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','restricted','suspended','deleted','pendingVerification')),
  role text NOT NULL DEFAULT 'user' CHECK (role IN ('user','reviewer','admin')),
  country_code char(2) CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$'),
  country_verified_at timestamptz,
  referral_code text NOT NULL UNIQUE,
  development_only boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_active_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK (version > 0)
);
CREATE TABLE auth_identities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id),
  issuer text NOT NULL, subject text NOT NULL CHECK (octet_length(subject) BETWEEN 1 AND 255),
  created_at timestamptz NOT NULL DEFAULT now(), UNIQUE (issuer,subject)
);
CREATE INDEX identities_user_idx ON auth_identities(user_id);
CREATE TABLE user_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id),
  identity_id uuid NOT NULL REFERENCES auth_identities(id), token_hash char(64) NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL, revoked_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
  ip_hash char(64), device_hash char(64), CHECK (expires_at > created_at), UNIQUE(id,user_id)
);
CREATE INDEX sessions_user_expiry_idx ON user_sessions(user_id,expires_at) WHERE revoked_at IS NULL;
CREATE TABLE wallets (
  user_id uuid PRIMARY KEY REFERENCES users(id), unit text NOT NULL DEFAULT 'ShareCoin' CHECK (unit='ShareCoin'),
  cached_available bigint NOT NULL DEFAULT 0 CHECK (cached_available BETWEEN 0 AND 9007199254740991),
  ledger_count bigint NOT NULL DEFAULT 0 CHECK (ledger_count >= 0), revision bigint NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), actor_kind text NOT NULL CHECK (actor_kind IN ('user','admin','provider','system','anonymous')),
  actor_id text, account_id uuid REFERENCES users(id), action text NOT NULL, entity_type text NOT NULL, entity_id text,
  request_id uuid NOT NULL, reason text NOT NULL CHECK (octet_length(reason) BETWEEN 1 AND 1000),
  context jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(context)='object' AND octet_length(context::text) <= 8192),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_account_time_idx ON audit_logs(account_id,created_at DESC,id);
CREATE INDEX audit_entity_idx ON audit_logs(entity_type,entity_id);
CREATE TABLE providers (
  id text PRIMARY KEY CHECK (id ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$'),
  kind text NOT NULL CHECK (kind IN ('ad','offer','promotion','payout','internal')),
  name text NOT NULL, protocol text NOT NULL DEFAULT 'sharebondhu-hmac-v1' CHECK (protocol IN ('sharebondhu-hmac-v1','internal')),
  secret_ref text, enabled boolean NOT NULL DEFAULT false, tracking_parameter text NOT NULL DEFAULT 'sb_start' CHECK (tracking_parameter ~ '^[A-Za-z][A-Za-z0-9_]{0,31}$'),
  development_only boolean NOT NULL DEFAULT false, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (kind='internal' OR secret_ref IS NOT NULL)
);
CREATE TABLE reward_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), source text NOT NULL CHECK (source IN ('adReward','offerReward','promotionReward','referralReward','dailyReward')),
  policy_key text NOT NULL UNIQUE, version bigint NOT NULL DEFAULT 1, provider_id text REFERENCES providers(id),
  reward_coins bigint NOT NULL CHECK (reward_coins BETWEEN 0 AND 9007199254740991),
  enabled boolean NOT NULL DEFAULT false, auto_approve boolean NOT NULL DEFAULT false,
  daily_limit integer NOT NULL DEFAULT 1 CHECK (daily_limit BETWEEN 1 AND 1000),
  cooldown_seconds integer NOT NULL DEFAULT 0 CHECK (cooldown_seconds BETWEEN 0 AND 86400),
  session_seconds integer NOT NULL DEFAULT 600 CHECK (session_seconds BETWEEN 30 AND 86400),
  minimum_account_age_seconds integer NOT NULL DEFAULT 0 CHECK (minimum_account_age_seconds BETWEEN 0 AND 31536000),
  qualifying_events integer NOT NULL DEFAULT 1 CHECK (qualifying_events BETWEEN 1 AND 100),
  block_shared_risk boolean NOT NULL DEFAULT true,
  countries text[] NOT NULL DEFAULT '{}', platforms text[] NOT NULL DEFAULT ARRAY['android','ios'],
  ad_unit text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (platforms <@ ARRAY['android','ios']::text[])
);
CREATE TABLE daily_reward_steps (
  policy_id uuid NOT NULL REFERENCES reward_policies(id), day integer NOT NULL CHECK (day BETWEEN 1 AND 7),
  reward_coins bigint NOT NULL CHECK (reward_coins BETWEEN 0 AND 9007199254740991), PRIMARY KEY(policy_id,day)
);
CREATE TABLE withdrawal_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), version bigint NOT NULL DEFAULT 1, active boolean NOT NULL DEFAULT false,
  minimum_coins bigint NOT NULL CHECK (minimum_coins BETWEEN 1 AND 9007199254740991),
  maximum_coins bigint NOT NULL CHECK (maximum_coins BETWEEN minimum_coins AND 9007199254740991),
  coin_units bigint NOT NULL CHECK (coin_units BETWEEN 1 AND 9007199254740991), minor_units bigint NOT NULL CHECK (minor_units BETWEEN 1 AND 9007199254740991),
  currency char(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'), scale integer NOT NULL DEFAULT 2 CHECK (scale BETWEEN 0 AND 6),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX one_active_withdrawal_policy ON withdrawal_policies(active) WHERE active;
CREATE TABLE payout_methods (
  policy_id uuid NOT NULL REFERENCES withdrawal_policies(id), method text NOT NULL CHECK (method IN ('bkash','nagad','rocket','paypal','bank')),
  provider_id text REFERENCES providers(id), enabled boolean NOT NULL DEFAULT false,
  fee_minor bigint NOT NULL DEFAULT 0 CHECK (fee_minor BETWEEN 0 AND 9007199254740991), PRIMARY KEY(policy_id,method)
);
CREATE TABLE payout_destinations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id),
  method text NOT NULL CHECK (method IN ('bkash','nagad','rocket','paypal','bank')), provider_id text NOT NULL REFERENCES providers(id),
  provider_recipient_ref text NOT NULL CHECK (octet_length(provider_recipient_ref) BETWEEN 1 AND 128),
  masked_destination text NOT NULL CHECK (masked_destination LIKE '%***%' AND masked_destination !~ '[0-9]{5}'),
  enabled boolean NOT NULL DEFAULT false, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(id,user_id), UNIQUE(user_id,method,provider_id)
);
CREATE TABLE offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), title text NOT NULL, short_description text NOT NULL, description text NOT NULL,
  publisher text NOT NULL, category text NOT NULL CHECK (category IN ('installApps','games','registerAndEarn','surveys','shopping','finance','education','entertainment','featured','limitedTime')),
  provider_id text NOT NULL REFERENCES providers(id), policy_id uuid NOT NULL REFERENCES reward_policies(id),
  reward_coins bigint NOT NULL CHECK (reward_coins BETWEEN 1 AND 9007199254740991), estimated_minutes integer NOT NULL CHECK (estimated_minutes BETWEEN 0 AND 525600),
  countries text[] NOT NULL DEFAULT '{}', platforms text[] NOT NULL CHECK (platforms <@ ARRAY['android','ios']::text[]),
  status text NOT NULL DEFAULT 'unavailable' CHECK (status IN ('available','unavailable')),
  featured boolean NOT NULL DEFAULT false, sort_priority integer NOT NULL DEFAULT 0 CHECK (sort_priority BETWEEN 0 AND 1000000),
  icon_url text, install_url text, destination_url text, tracking_url text, instructions text[] NOT NULL DEFAULT '{}', terms text[] NOT NULL DEFAULT '{}',
  tracking_metadata jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(tracking_metadata)='object'),
  starts_at timestamptz NOT NULL, expires_at timestamptz NOT NULL, development_only boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CHECK (expires_at > starts_at), UNIQUE(id,provider_id)
);
CREATE INDEX offers_catalog_idx ON offers(status,featured DESC,sort_priority,id);
CREATE INDEX offers_category_reward_idx ON offers(category,reward_coins DESC,id);
CREATE INDEX offers_provider_idx ON offers(provider_id,status);
CREATE INDEX offers_country_idx ON offers USING gin(countries);
CREATE INDEX offers_platform_idx ON offers USING gin(platforms);
CREATE INDEX offers_search_idx ON offers USING gin(to_tsvector('simple',title || ' ' || publisher || ' ' || description));
CREATE TABLE offer_starts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id), offer_id uuid NOT NULL REFERENCES offers(id),
  provider_id text NOT NULL REFERENCES providers(id), quoted_coins bigint NOT NULL CHECK (quoted_coins BETWEEN 1 AND 9007199254740991),
  policy_id uuid NOT NULL REFERENCES reward_policies(id), policy_version bigint NOT NULL,
  event_id uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE, claim_key text NOT NULL UNIQUE, idempotency_key text NOT NULL,
  status text NOT NULL DEFAULT 'started' CHECK (status IN ('started','pending','completed','rejected')),
  expires_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id,offer_id), UNIQUE(id,user_id), UNIQUE(user_id,idempotency_key)
);
CREATE INDEX offer_starts_user_idx ON offer_starts(user_id,created_at DESC);
CREATE TABLE promotions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), title text NOT NULL, description text NOT NULL, advertiser text NOT NULL, cta text NOT NULL,
  provider_id text NOT NULL REFERENCES providers(id), policy_id uuid NOT NULL REFERENCES reward_policies(id),
  reward_coins bigint NOT NULL CHECK (reward_coins BETWEEN 1 AND 9007199254740991), image_url text, destination_url text NOT NULL,
  countries text[] NOT NULL DEFAULT '{}', platforms text[] NOT NULL DEFAULT ARRAY['android','ios'],
  status text NOT NULL DEFAULT 'unavailable' CHECK (status IN ('scheduled','active','paused','expired','completed','unavailable')),
  starts_at timestamptz NOT NULL, ends_at timestamptz NOT NULL, development_only boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CHECK (ends_at > starts_at)
);
CREATE INDEX promotions_feed_idx ON promotions(status,starts_at,id);
CREATE TABLE reward_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id), policy_id uuid NOT NULL REFERENCES reward_policies(id),
  policy_version bigint NOT NULL, source text NOT NULL CHECK (source IN ('adReward','dailyReward','promotionReward')),
  provider_id text NOT NULL REFERENCES providers(id), target_id text NOT NULL, quoted_coins bigint NOT NULL CHECK (quoted_coins BETWEEN 0 AND 9007199254740991),
  event_id uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE, event_key text NOT NULL UNIQUE, request_key text NOT NULL,
  issued_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL, not_before timestamptz NOT NULL,
  availability text NOT NULL CHECK (availability IN ('eligible','cooldown','dailyLimit','expired','unavailable','restricted')),
  quota_day date NOT NULL, used_today integer NOT NULL CHECK (used_today >= 0), daily_limit integer NOT NULL CHECK (daily_limit BETWEEN 1 AND 1000),
  provider_event_hint text, launch_url text, ad_unit text, UNIQUE(user_id,request_key), UNIQUE(id,user_id),
  CHECK (expires_at > not_before AND not_before >= issued_at),
  CHECK (availability <> 'eligible' OR (quoted_coins > 0 AND used_today < daily_limit))
);
CREATE UNIQUE INDEX daily_session_once ON reward_sessions(user_id,policy_id,quota_day) WHERE source='dailyReward' AND availability='eligible';
CREATE INDEX reward_sessions_user_idx ON reward_sessions(user_id,issued_at DESC);
CREATE TABLE reward_quota (
  user_id uuid NOT NULL REFERENCES users(id), policy_id uuid NOT NULL REFERENCES reward_policies(id), quota_day date NOT NULL,
  issued integer NOT NULL DEFAULT 0 CHECK (issued >= 0), last_issued_at timestamptz, PRIMARY KEY(user_id,policy_id,quota_day)
);
CREATE TABLE promotion_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id), promotion_id uuid NOT NULL REFERENCES promotions(id),
  reward_session_id uuid NOT NULL REFERENCES reward_sessions(id), kind text NOT NULL DEFAULT 'started' CHECK (kind='started'),
  created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(reward_session_id)
);
CREATE TABLE referrals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), inviter_id uuid NOT NULL REFERENCES users(id), invitee_id uuid NOT NULL UNIQUE REFERENCES users(id),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','qualified','rejected','rewarded')),
  qualification_reason text, qualified_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (inviter_id <> invitee_id), UNIQUE(id,inviter_id)
);
CREATE INDEX referrals_inviter_idx ON referrals(inviter_id,status,created_at);
CREATE TABLE withdrawal_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id), destination_id uuid NOT NULL,
  policy_id uuid NOT NULL REFERENCES withdrawal_policies(id), policy_version bigint NOT NULL,
  provider_id text NOT NULL REFERENCES providers(id), method text NOT NULL CHECK (method IN ('bkash','nagad','rocket','paypal','bank')),
  requested_coins bigint NOT NULL CHECK (requested_coins BETWEEN 1 AND 9007199254740991), coin_units bigint NOT NULL CHECK (coin_units > 0),
  minor_units bigint NOT NULL CHECK (minor_units > 0), currency char(3) NOT NULL, scale integer NOT NULL CHECK (scale BETWEEN 0 AND 6),
  fee_minor bigint NOT NULL CHECK (fee_minor >= 0), final_payout_minor bigint NOT NULL CHECK (final_payout_minor BETWEEN 0 AND 9007199254740991),
  masked_destination text NOT NULL CHECK (masked_destination LIKE '%***%'),
  status text NOT NULL DEFAULT 'requested' CHECK (status IN ('requested','pending','approved','processing','paid','rejected','cancelled')),
  idempotency_key text NOT NULL, server_reference text, rejection_reason text, paid_provider_event_id uuid,
  requested_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(destination_id,user_id) REFERENCES payout_destinations(id,user_id), UNIQUE(id,user_id), UNIQUE(user_id,idempotency_key),
  CHECK (final_payout_minor = floor(requested_coins::numeric * minor_units / coin_units) - fee_minor),
  CHECK (status <> 'paid' OR server_reference IS NOT NULL), CHECK (status <> 'rejected' OR rejection_reason IS NOT NULL)
);
CREATE UNIQUE INDEX one_active_withdrawal ON withdrawal_requests(user_id) WHERE status IN ('requested','pending','approved','processing');
CREATE INDEX withdrawals_history_idx ON withdrawal_requests(user_id,requested_at DESC,id);
CREATE TABLE provider_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), provider_id text NOT NULL REFERENCES providers(id), provider_event_id text NOT NULL,
  event_type text NOT NULL CHECK (event_type IN ('adCompletion','offerCompletion','promotionConversion','payoutResult')),
  user_id uuid NOT NULL REFERENCES users(id), reward_session_id uuid, offer_start_id uuid, withdrawal_id uuid,
  body_hash char(64) NOT NULL, signed_timestamp timestamptz NOT NULL, verified_at timestamptz NOT NULL DEFAULT now(),
  outcome text CHECK (outcome IN ('paid','rejected')), external_reference text,
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload)='object' AND octet_length(payload::text) <= 65536),
  UNIQUE(provider_id,provider_event_id), UNIQUE(id,user_id),
  FOREIGN KEY(reward_session_id,user_id) REFERENCES reward_sessions(id,user_id),
  FOREIGN KEY(offer_start_id,user_id) REFERENCES offer_starts(id,user_id),
  FOREIGN KEY(withdrawal_id,user_id) REFERENCES withdrawal_requests(id,user_id),
  CHECK (num_nonnulls(reward_session_id,offer_start_id,withdrawal_id)=1)
);
ALTER TABLE withdrawal_requests ADD CONSTRAINT withdrawal_provider_proof_fk FOREIGN KEY(paid_provider_event_id,user_id) REFERENCES provider_events(id,user_id) DEFERRABLE INITIALLY DEFERRED;
CREATE TABLE reward_events (
  id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id), source text NOT NULL CHECK (source IN ('adReward','offerReward','promotionReward','referralReward','dailyReward')),
  provider_id text NOT NULL REFERENCES providers(id), provider_event_id text NOT NULL, provider_event_ref uuid,
  target_id text NOT NULL, quoted_coins bigint NOT NULL CHECK (quoted_coins BETWEEN 1 AND 9007199254740991),
  policy_id uuid NOT NULL REFERENCES reward_policies(id), policy_version bigint NOT NULL,
  reward_session_id uuid, offer_start_id uuid, referral_id uuid,
  status text NOT NULL DEFAULT 'received' CHECK (status IN ('received','validating','pending','approved','rejected','reversed','reconciled')),
  transaction_id uuid, idempotency_key text NOT NULL, client_occurred_at timestamptz,
  reason text, metadata jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(metadata)='object'),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(id,user_id), UNIQUE(user_id,idempotency_key), UNIQUE(provider_id,provider_event_id),
  FOREIGN KEY(provider_event_ref,user_id) REFERENCES provider_events(id,user_id),
  FOREIGN KEY(reward_session_id,user_id) REFERENCES reward_sessions(id,user_id),
  FOREIGN KEY(offer_start_id,user_id) REFERENCES offer_starts(id,user_id),
  FOREIGN KEY(referral_id,user_id) REFERENCES referrals(id,inviter_id),
  CHECK (num_nonnulls(reward_session_id,offer_start_id,referral_id)=1),
  CHECK ((status IN ('approved','reconciled','reversed')) = (transaction_id IS NOT NULL))
);
CREATE UNIQUE INDEX reward_session_event_once ON reward_events(reward_session_id) WHERE reward_session_id IS NOT NULL;
CREATE UNIQUE INDEX offer_start_event_once ON reward_events(offer_start_id) WHERE offer_start_id IS NOT NULL;
CREATE UNIQUE INDEX referral_event_once ON reward_events(referral_id) WHERE referral_id IS NOT NULL;
CREATE INDEX rewards_user_status_idx ON reward_events(user_id,status,created_at DESC,id);
CREATE TABLE wallet_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  user_id uuid NOT NULL REFERENCES wallets(user_id), amount bigint NOT NULL CHECK (amount BETWEEN 1 AND 9007199254740991),
  direction text NOT NULL CHECK (direction IN ('credit','debit')),
  entry_type text NOT NULL CHECK (entry_type IN ('reward','reward_reversal','withdrawal_hold','withdrawal_release','admin_adjustment')),
  source text NOT NULL CHECK (source IN ('adReward','offerReward','promotionReward','referralReward','dailyReward','bonus','withdrawal','reversal','administrativeAdjustment')),
  status text NOT NULL DEFAULT 'completed' CHECK (status='completed'),
  reference_id text NOT NULL, reference_key text NOT NULL, idempotency_key text NOT NULL, description text NOT NULL,
  reward_event_id uuid, withdrawal_id uuid, reversal_of uuid UNIQUE, audit_id uuid NOT NULL UNIQUE REFERENCES audit_logs(id),
  metadata jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(metadata)='object'),
  created_at timestamptz NOT NULL DEFAULT now(), processed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(id,user_id), UNIQUE(user_id,entry_type,idempotency_key), UNIQUE(user_id,entry_type,reference_key),
  FOREIGN KEY(reward_event_id,user_id) REFERENCES reward_events(id,user_id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY(withdrawal_id,user_id) REFERENCES withdrawal_requests(id,user_id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY(reversal_of,user_id) REFERENCES wallet_transactions(id,user_id),
  CHECK ((entry_type='reward') = (reward_event_id IS NOT NULL)),
  CHECK ((entry_type IN ('withdrawal_hold','withdrawal_release')) = (withdrawal_id IS NOT NULL)),
  CHECK ((entry_type IN ('reward_reversal','withdrawal_release')) = (reversal_of IS NOT NULL))
);
ALTER TABLE reward_events ADD CONSTRAINT event_transaction_fk FOREIGN KEY(transaction_id,user_id) REFERENCES wallet_transactions(id,user_id) DEFERRABLE INITIALLY DEFERRED;
CREATE INDEX ledger_user_time_idx ON wallet_transactions(user_id,created_at DESC,id);
CREATE INDEX ledger_user_kind_idx ON wallet_transactions(user_id,entry_type,direction);
CREATE TABLE idempotency_keys (
  actor_scope text NOT NULL, operation text NOT NULL, key text NOT NULL CHECK (octet_length(key) BETWEEN 1 AND 128),
  payload_hash char(64) NOT NULL, response jsonb, created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
  PRIMARY KEY(actor_scope,operation,key), CHECK (expires_at > created_at)
);
CREATE TABLE risk_flags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id), code text NOT NULL,
  blocking boolean NOT NULL DEFAULT false, active boolean NOT NULL DEFAULT true, context jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(), resolved_at timestamptz, UNIQUE(user_id,code)
);
CREATE INDEX risk_active_idx ON risk_flags(user_id) WHERE active;
CREATE TABLE rate_limit_buckets (
  scope_hash char(64) NOT NULL, action text NOT NULL, bucket bigint NOT NULL, count integer NOT NULL CHECK (count > 0), expires_at timestamptz NOT NULL,
  PRIMARY KEY(scope_hash,action,bucket)
);
CREATE INDEX rate_expiry_idx ON rate_limit_buckets(expires_at);
CREATE TABLE system_revision (id boolean PRIMARY KEY DEFAULT true CHECK (id), revision bigint NOT NULL DEFAULT 1);
INSERT INTO system_revision(id) VALUES (true);

CREATE FUNCTION prevent_mutation() RETURNS trigger LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN RAISE EXCEPTION 'append-only record' USING ERRCODE='23514'; END $$;
CREATE TRIGGER ledger_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON wallet_transactions FOR EACH STATEMENT EXECUTE FUNCTION prevent_mutation();
CREATE TRIGGER audit_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON audit_logs FOR EACH STATEMENT EXECUTE FUNCTION prevent_mutation();
CREATE TRIGGER provider_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON provider_events FOR EACH STATEMENT EXECUTE FUNCTION prevent_mutation();
CREATE TRIGGER promotion_tracking_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON promotion_events FOR EACH STATEMENT EXECUTE FUNCTION prevent_mutation();

CREATE FUNCTION guard_wallet_projection() RETURNS trigger LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  IF pg_trigger_depth() < 2 THEN RAISE EXCEPTION 'wallet projection must follow ledger' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER wallet_projection_guard BEFORE UPDATE ON wallets FOR EACH ROW EXECUTE FUNCTION guard_wallet_projection();
CREATE FUNCTION ledger_insert_guard() RETURNS trigger LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
DECLARE balance numeric; original wallet_transactions; expected reward_events;
BEGIN
  PERFORM 1 FROM wallets WHERE user_id=NEW.user_id FOR UPDATE;
  SELECT COALESCE(SUM(CASE direction WHEN 'credit' THEN amount::numeric ELSE -amount::numeric END),0) INTO balance FROM wallet_transactions WHERE user_id=NEW.user_id;
  balance := balance + CASE NEW.direction WHEN 'credit' THEN NEW.amount ELSE -NEW.amount END;
  IF balance < 0 OR balance > 9007199254740991 THEN RAISE EXCEPTION 'balance invariant' USING ERRCODE='23514'; END IF;
  IF NEW.reversal_of IS NOT NULL THEN
    SELECT * INTO original FROM wallet_transactions WHERE id=NEW.reversal_of AND user_id=NEW.user_id;
    IF original.id IS NULL OR original.amount<>NEW.amount OR original.direction=NEW.direction OR original.reversal_of IS NOT NULL THEN
      RAISE EXCEPTION 'invalid reversal' USING ERRCODE='23514';
    END IF;
  END IF;
  IF NEW.entry_type='reward' THEN
    SELECT * INTO expected FROM reward_events WHERE id=NEW.reward_event_id AND user_id=NEW.user_id;
    IF expected.id IS NULL OR expected.quoted_coins<>NEW.amount OR NEW.direction<>'credit' OR expected.source<>NEW.source THEN
      RAISE EXCEPTION 'reward ledger mismatch' USING ERRCODE='23514';
    END IF;
  END IF;
  IF NEW.entry_type='withdrawal_hold' AND (NEW.direction<>'debit' OR NEW.source<>'withdrawal') THEN RAISE EXCEPTION 'invalid hold' USING ERRCODE='23514'; END IF;
  IF NEW.entry_type='withdrawal_release' AND (NEW.direction<>'credit' OR original.entry_type<>'withdrawal_hold') THEN RAISE EXCEPTION 'invalid release' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ledger_guard BEFORE INSERT ON wallet_transactions FOR EACH ROW EXECUTE FUNCTION ledger_insert_guard();
CREATE FUNCTION update_wallet_projection() RETURNS trigger LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
DECLARE balance numeric; entries bigint;
BEGIN
  SELECT COALESCE(SUM(CASE direction WHEN 'credit' THEN amount::numeric ELSE -amount::numeric END),0),count(*) INTO balance,entries FROM wallet_transactions WHERE user_id=NEW.user_id;
  UPDATE wallets SET cached_available=balance,ledger_count=entries,revision=revision+1,updated_at=now() WHERE user_id=NEW.user_id;
  RETURN NEW;
END $$;
CREATE TRIGGER ledger_projection AFTER INSERT ON wallet_transactions FOR EACH ROW EXECUTE FUNCTION update_wallet_projection();

CREATE FUNCTION guard_reward_transition() RETURNS trigger LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  IF ROW(NEW.user_id,NEW.source,NEW.provider_id,NEW.target_id,NEW.quoted_coins,NEW.policy_id,NEW.policy_version,NEW.idempotency_key) IS DISTINCT FROM ROW(OLD.user_id,OLD.source,OLD.provider_id,OLD.target_id,OLD.quoted_coins,OLD.policy_id,OLD.policy_version,OLD.idempotency_key) THEN
    RAISE EXCEPTION 'immutable reward identity' USING ERRCODE='23514';
  END IF;
  IF NEW.status<>OLD.status AND NOT (
    (OLD.status='received' AND NEW.status IN ('validating','pending','rejected')) OR
    (OLD.status='validating' AND NEW.status IN ('pending','approved','rejected')) OR
    (OLD.status='pending' AND NEW.status IN ('validating','approved','rejected')) OR
    (OLD.status='approved' AND NEW.status IN ('reconciled','reversed')) OR
    (OLD.status='reconciled' AND NEW.status='reversed')) THEN RAISE EXCEPTION 'invalid reward transition' USING ERRCODE='23514'; END IF;
  NEW.updated_at=now(); RETURN NEW;
END $$;
CREATE TRIGGER reward_transition BEFORE UPDATE ON reward_events FOR EACH ROW EXECUTE FUNCTION guard_reward_transition();
CREATE FUNCTION guard_withdrawal_transition() RETURNS trigger LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  IF ROW(NEW.user_id,NEW.destination_id,NEW.provider_id,NEW.requested_coins,NEW.coin_units,NEW.minor_units,NEW.fee_minor,NEW.final_payout_minor,NEW.idempotency_key) IS DISTINCT FROM ROW(OLD.user_id,OLD.destination_id,OLD.provider_id,OLD.requested_coins,OLD.coin_units,OLD.minor_units,OLD.fee_minor,OLD.final_payout_minor,OLD.idempotency_key) THEN
    RAISE EXCEPTION 'immutable withdrawal terms' USING ERRCODE='23514';
  END IF;
  IF NEW.status<>OLD.status AND NOT (
    (OLD.status='requested' AND NEW.status IN ('pending','approved','rejected','cancelled')) OR
    (OLD.status='pending' AND NEW.status IN ('approved','rejected','cancelled')) OR
    (OLD.status='approved' AND NEW.status IN ('processing','rejected')) OR
    (OLD.status='processing' AND NEW.status IN ('paid','rejected'))) THEN RAISE EXCEPTION 'invalid withdrawal transition' USING ERRCODE='23514'; END IF;
  NEW.updated_at=now(); RETURN NEW;
END $$;
CREATE TRIGGER withdrawal_transition BEFORE UPDATE ON withdrawal_requests FOR EACH ROW EXECUTE FUNCTION guard_withdrawal_transition();

CREATE FUNCTION check_reward_commit() RETURNS trigger LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
DECLARE event reward_events;
BEGIN
  SELECT * INTO event FROM reward_events WHERE id=NEW.id;
  IF event.status IN ('approved','reconciled','reversed') THEN
    IF NOT EXISTS (SELECT 1 FROM wallet_transactions WHERE id=event.transaction_id AND reward_event_id=event.id AND user_id=event.user_id AND amount=event.quoted_coins) THEN
      RAISE EXCEPTION 'reward missing ledger' USING ERRCODE='23514';
    END IF;
    IF event.source IN ('adReward','offerReward','promotionReward') AND event.provider_event_ref IS NULL THEN RAISE EXCEPTION 'reward missing provider evidence' USING ERRCODE='23514'; END IF;
    IF event.status='reversed' AND NOT EXISTS (SELECT 1 FROM wallet_transactions WHERE reversal_of=event.transaction_id) THEN RAISE EXCEPTION 'missing reversal' USING ERRCODE='23514'; END IF;
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER reward_commit AFTER INSERT OR UPDATE ON reward_events DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION check_reward_commit();
CREATE FUNCTION check_withdrawal_commit() RETURNS trigger LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
DECLARE request withdrawal_requests; hold wallet_transactions; released boolean;
BEGIN
  SELECT * INTO request FROM withdrawal_requests WHERE id=NEW.id;
  SELECT * INTO hold FROM wallet_transactions WHERE withdrawal_id=request.id AND entry_type='withdrawal_hold';
  IF hold.id IS NULL OR hold.amount<>request.requested_coins THEN RAISE EXCEPTION 'missing withdrawal hold' USING ERRCODE='23514'; END IF;
  SELECT EXISTS(SELECT 1 FROM wallet_transactions WHERE reversal_of=hold.id AND entry_type='withdrawal_release') INTO released;
  IF (request.status IN ('rejected','cancelled'))<>released THEN RAISE EXCEPTION 'withdrawal hold/release mismatch' USING ERRCODE='23514'; END IF;
  IF request.status='paid' AND NOT EXISTS (SELECT 1 FROM provider_events WHERE id=request.paid_provider_event_id AND user_id=request.user_id AND provider_id=request.provider_id AND withdrawal_id=request.id AND event_type='payoutResult' AND outcome='paid') THEN
    RAISE EXCEPTION 'paid withdrawal requires verified provider result' USING ERRCODE='23514';
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER withdrawal_commit AFTER INSERT OR UPDATE ON withdrawal_requests DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION check_withdrawal_commit();

CREATE FUNCTION prevent_referral_cycle() RETURNS trigger LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  IF EXISTS (WITH RECURSIVE chain(id) AS (SELECT NEW.inviter_id UNION SELECT r.inviter_id FROM referrals r JOIN chain c ON r.invitee_id=c.id) SELECT 1 FROM chain WHERE id=NEW.invitee_id) THEN
    RAISE EXCEPTION 'referral cycle' USING ERRCODE='23514';
  END IF; RETURN NEW;
END $$;
CREATE TRIGGER referral_cycle BEFORE INSERT ON referrals FOR EACH ROW EXECUTE FUNCTION prevent_referral_cycle();
CREATE FUNCTION bump_catalog() RETURNS trigger LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN UPDATE system_revision SET revision=revision+1 WHERE id=true; RETURN NULL; END $$;
CREATE TRIGGER offers_revision AFTER INSERT OR UPDATE OR DELETE ON offers FOR EACH STATEMENT EXECUTE FUNCTION bump_catalog();
CREATE TRIGGER promotions_revision AFTER INSERT OR UPDATE OR DELETE ON promotions FOR EACH STATEMENT EXECUTE FUNCTION bump_catalog();

INSERT INTO providers(id,kind,name,protocol,enabled) VALUES ('server-daily','internal','Backend daily policy','internal',true),('server-referral','internal','Backend referral policy','internal',true);

CREATE FUNCTION check_ledger_commit() RETURNS trigger LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
DECLARE event reward_events; request withdrawal_requests;
BEGIN
  IF NEW.entry_type='reward' THEN
    SELECT * INTO event FROM reward_events WHERE id=NEW.reward_event_id;
    IF event.transaction_id IS DISTINCT FROM NEW.id OR event.status NOT IN ('approved','reconciled','reversed') THEN RAISE EXCEPTION 'ledger without approved event' USING ERRCODE='23514'; END IF;
  END IF;
  IF NEW.entry_type='reward_reversal' THEN
    SELECT * INTO event FROM reward_events WHERE transaction_id=NEW.reversal_of;
    IF event.id IS NOT NULL AND event.status<>'reversed' THEN RAISE EXCEPTION 'event reversal mismatch' USING ERRCODE='23514'; END IF;
  END IF;
  IF NEW.withdrawal_id IS NOT NULL THEN
    SELECT * INTO request FROM withdrawal_requests WHERE id=NEW.withdrawal_id;
    IF NEW.amount<>request.requested_coins OR (NEW.entry_type='withdrawal_release' AND request.status NOT IN ('rejected','cancelled')) THEN RAISE EXCEPTION 'withdrawal ledger mismatch' USING ERRCODE='23514'; END IF;
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER ledger_commit AFTER INSERT ON wallet_transactions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION check_ledger_commit();
