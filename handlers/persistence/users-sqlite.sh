#!/usr/bin/env bash
# shellcheck disable=SC2034

users_sqlite_path() {
	USERS_SQLITE_FILE=${BASH_HTTP_USERS_SQLITE_FILE:-$ROOT_DIR/data/users.sqlite}
}

users_sqlite_query() {
	local sql=$1

	users_sqlite_path
	sqlite3 -batch -bail -noheader -cmd '.timeout 5000' "$USERS_SQLITE_FILE" "$sql"
}

users_repository_initialize() {
	local data_dir

	users_sqlite_path
	data_dir=${USERS_SQLITE_FILE%/*}
	[[ $data_dir != "$USERS_SQLITE_FILE" && -d $data_dir && -w $data_dir ]] || return 1
	sqlite3 -batch -bail "$USERS_SQLITE_FILE" <"$ROOT_DIR/handlers/persistence/users-sqlite-schema.sql"
}

users_repository_list() {
	USERS_REPOSITORY_RESULT=$(users_sqlite_query \
		"SELECT COALESCE(json_group_array(json(document)), '[]') FROM (SELECT document FROM users ORDER BY id);") || return 1
}

users_repository_find_by_id() {
	local user_id=$1

	[[ $user_id =~ ^[0-9]+$ ]] || return 1
	USERS_REPOSITORY_RESULT=$(users_sqlite_query "SELECT document FROM users WHERE id = $user_id;") || return 1
	if [[ -n $USERS_REPOSITORY_RESULT ]]; then
		USERS_REPOSITORY_FOUND=true
	else
		USERS_REPOSITORY_FOUND=false
	fi
}

users_repository_create() {
	local body_file=$1
	local body_hex

	body_hex=$(od -An -v -tx1 "$body_file" | tr -d ' \n') || return 1
	USERS_REPOSITORY_RESULT=$(users_sqlite_query \
		"BEGIN IMMEDIATE;
INSERT INTO users (document) VALUES (CAST(X'$body_hex' AS TEXT));
UPDATE users SET document = json_set(document, '$.id', id) WHERE id = last_insert_rowid();
SELECT document FROM users WHERE id = last_insert_rowid();
COMMIT;") || return 1
}

users_repository_delete() {
	local user_id=$1
	local deleted

	[[ $user_id =~ ^[0-9]+$ ]] || return 1
	deleted=$(users_sqlite_query \
		"BEGIN IMMEDIATE;
DELETE FROM users WHERE id = $user_id;
SELECT changes();
COMMIT;") || return 1
	if [[ $deleted == 1 ]]; then
		USERS_REPOSITORY_DELETED=true
	else
		USERS_REPOSITORY_DELETED=false
	fi
}
