-- Track which gateway created each checkout (zeno | sonicpesa).
ALTER TABLE payment_intents
  ADD COLUMN IF NOT EXISTS payment_provider TEXT;

CREATE INDEX IF NOT EXISTS idx_payment_intents_provider ON payment_intents (payment_provider);

INSERT INTO app_settings (key, value)
VALUES ('payment_provider', 'zeno')
ON CONFLICT (key) DO NOTHING;
