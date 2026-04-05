-- Dart Color values are 32-bit unsigned; INTEGER is too small for full ARGB.
ALTER TABLE malipo_plans
  ALTER COLUMN accent1 TYPE BIGINT,
  ALTER COLUMN accent2 TYPE BIGINT;
