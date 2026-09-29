BEGIN IMMEDIATE;

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    document TEXT NOT NULL CHECK (json_valid(document) AND json_type(document) = 'object')
);

CREATE TABLE IF NOT EXISTS users_repository_metadata (
    key TEXT PRIMARY KEY
);

INSERT INTO users (id, document)
SELECT 1, '{"id":1,"name":"Ada Lovelace"}'
WHERE NOT EXISTS (
    SELECT 1 FROM users_repository_metadata WHERE key = 'initial-data-created'
);

INSERT INTO users (id, document)
SELECT 2, '{"id":2,"name":"Grace Hopper"}'
WHERE NOT EXISTS (
    SELECT 1 FROM users_repository_metadata WHERE key = 'initial-data-created'
);

INSERT OR IGNORE INTO users_repository_metadata (key)
VALUES ('initial-data-created');

COMMIT;
