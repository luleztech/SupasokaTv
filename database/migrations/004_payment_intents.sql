-- Durable payment ledger for idempotent premium activation.
-- Safe to re-run (PostgreSQL 11+).

CREATE TABLE IF NOT EXISTS payment_intents (
  order_id TEXT PRIMARY KEY,
  public_id TEXT,
  plan_id TEXT,
  amount_tzs BIGINT,
  buyer_phone TEXT,
  status TEXT NOT NULL DEFAULT 'PENDING',
  provider_status TEXT,
  activated_at_ms BIGINT,
  provider_payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_intents_status ON payment_intents (status);
CREATE INDEX IF NOT EXISTS idx_payment_intents_public_id ON payment_intents (public_id);
