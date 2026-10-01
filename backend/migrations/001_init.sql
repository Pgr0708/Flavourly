-- Flavourly API schema. Everything is anonymous: a device is a random install id + a hashed token.
-- Recipes, plans and lists never leave the phone (they live in Core Data / iCloud).

CREATE TABLE IF NOT EXISTS devices (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  install_id    VARCHAR(64)     NOT NULL,
  token_hash    CHAR(64)        NOT NULL,
  platform      VARCHAR(16)     NOT NULL DEFAULT 'ios',
  app_version   VARCHAR(20)     NULL,
  created_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  last_seen_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_devices_install (install_id),
  UNIQUE KEY uq_devices_token (token_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Free-plan counters: one row per device, feature and period (Monday of the week, or the day).
CREATE TABLE IF NOT EXISTS usage_counters (
  device_id     BIGINT UNSIGNED NOT NULL,
  feature       VARCHAR(32)     NOT NULL,
  period_start  DATE            NOT NULL,
  used          INT UNSIGNED    NOT NULL DEFAULT 0,
  updated_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (device_id, feature, period_start),
  KEY idx_usage_period (period_start),
  CONSTRAINT fk_usage_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
