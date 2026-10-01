-- Run once as root:  mysql -u root -p < deploy/setup-mysql.sql
-- Creates ONLY a new database and a new user for Flavourly. Existing databases and users are not touched.
-- Replace the password first (keep it the same as DB_PASSWORD in backend/.env).

CREATE DATABASE IF NOT EXISTS flavourly CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'flavourly_app'@'localhost' IDENTIFIED BY 'change-me-to-a-long-random-password';
CREATE USER IF NOT EXISTS 'flavourly_app'@'127.0.0.1' IDENTIFIED BY 'change-me-to-a-long-random-password';

-- Least privilege: only this database, only what the API and its migrations need.
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES ON flavourly.* TO 'flavourly_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES ON flavourly.* TO 'flavourly_app'@'127.0.0.1';
FLUSH PRIVILEGES;
