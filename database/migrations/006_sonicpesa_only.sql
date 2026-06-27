-- Remove ZenoPay: SonicPesa is the only payment gateway.
UPDATE app_settings SET value = 'sonicpesa' WHERE key = 'payment_provider' AND value IN ('zeno', 'zenopay');

INSERT INTO app_settings (key, value)
VALUES ('payment_provider', 'sonicpesa')
ON CONFLICT (key) DO UPDATE SET value = 'sonicpesa';

UPDATE payment_intents
SET payment_provider = 'sonicpesa'
WHERE payment_provider IS NULL
   OR payment_provider IN ('zeno', 'zenopay', 'Zeno', 'ZenoPay');
