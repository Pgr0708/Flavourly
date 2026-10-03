-- Shared dish library: any dish someone searched for, found once (TheMealDB or AI) and reused by everyone.
CREATE TABLE IF NOT EXISTS dishes (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  slug        VARCHAR(120)    NOT NULL,
  name        VARCHAR(160)    NOT NULL,
  country     CHAR(2)         NULL,
  source      VARCHAR(20)     NOT NULL,
  recipe      JSON            NOT NULL,
  hits        INT UNSIGNED    NOT NULL DEFAULT 0,
  created_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_dishes_slug (slug),
  KEY idx_dishes_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
