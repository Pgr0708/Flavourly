-- Premium "make it my way" variations of a dish: written by AI, shared with cooks in the same country
-- (same region first). Removed with the device that made them.
CREATE TABLE IF NOT EXISTS variations (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  base_slug   VARCHAR(120)    NOT NULL,
  base_title  VARCHAR(160)    NOT NULL,
  title       VARCHAR(160)    NOT NULL,
  change_text VARCHAR(200)    NOT NULL,
  country     CHAR(2)         NULL,
  region      VARCHAR(60)     NULL,
  recipe      JSON            NOT NULL,
  image_url   VARCHAR(600)    NULL,
  device_id   BIGINT UNSIGNED NOT NULL,
  tried       INT UNSIGNED    NOT NULL DEFAULT 0,
  created_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_variations_base (base_slug, country, tried),
  CONSTRAINT fk_variations_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- One "I tried it" per device per variation.
CREATE TABLE IF NOT EXISTS variation_tries (
  variation_id BIGINT UNSIGNED NOT NULL,
  device_id    BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (variation_id, device_id),
  CONSTRAINT fk_tries_variation FOREIGN KEY (variation_id) REFERENCES variations (id) ON DELETE CASCADE,
  CONSTRAINT fk_tries_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
