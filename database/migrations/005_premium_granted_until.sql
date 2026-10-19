-- One-shot premium grant marker — prevents re-grant after natural expiry.
-- Safe to re-run.

ALTER TABLE payment_intents ADD COLUMN IF NOT EXISTS premium_granted_until_ms BIGINT;

CREATE INDEX IF NOT EXISTS idx_payment_intents_ungranted
  ON payment_intents (public_id)
  WHERE premium_granted_until_ms IS NULL AND activated_at_ms IS NOT NULL;
