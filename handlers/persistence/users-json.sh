#!/usr/bin/env bash
# shellcheck disable=SC2034

users_json_path() {
	USERS_JSON_FILE=${BASH_HTTP_USERS_FILE:-$ROOT_DIR/data/users.json}
}

users_json_read_all() {
	users_json_path
	[[ -r $USERS_JSON_FILE ]] || return 1
	USERS_JSON_DATA=$(jq --compact-output 'if type == "array" then . else error("users data must be an array") end' "$USERS_JSON_FILE" 2>/dev/null) || return 1
}

users_json_write_all() {
	local value=$1
	local data_dir temporary_file

	users_json_path
	data_dir=${USERS_JSON_FILE%/*}
	[[ $data_dir != "$USERS_JSON_FILE" && -d $data_dir && -w $data_dir ]] || return 1
	temporary_file=$(mktemp "$data_dir/.users.XXXXXX") || return 1
	if ! jq --compact-output '.' <<<"$value" >"$temporary_file" 2>/dev/null; then
		rm -f "$temporary_file"
		return 1
	fi
	chmod 0644 "$temporary_file" || {
		rm -f "$temporary_file"
		return 1
	}
	if ! mv "$temporary_file" "$USERS_JSON_FILE"; then
		rm -f "$temporary_file"
		return 1
	fi
}

users_repository_initialize() {
	users_json_read_all
}

users_repository_list() {
	users_json_read_all || return 1
	USERS_REPOSITORY_RESULT=$USERS_JSON_DATA
}

users_repository_find_by_id() {
	local user_id=$1

	users_json_read_all || return 1
	USERS_REPOSITORY_RESULT=$(jq --compact-output --arg id "$user_id" 'first(.[] | select((.id | tostring) == $id)) // empty' <<<"$USERS_JSON_DATA") || return 1
	if [[ -n $USERS_REPOSITORY_RESULT ]]; then
		USERS_REPOSITORY_FOUND=true
	else
		USERS_REPOSITORY_FOUND=false
	fi
}

users_repository_create() {
	local body_file=$1
	local next_id updated_users

	users_json_read_all || return 1
	next_id=$(jq '[.[].id | tonumber?] | max // 0 | . + 1' <<<"$USERS_JSON_DATA") || return 1
	USERS_REPOSITORY_RESULT=$(jq --compact-output --argjson id "$next_id" '. + {id: $id}' "$body_file") || return 1
	updated_users=$(jq --compact-output --argjson user "$USERS_REPOSITORY_RESULT" '. + [$user]' <<<"$USERS_JSON_DATA") || return 1
	users_json_write_all "$updated_users"
}

users_repository_delete() {
	local user_id=$1
	local updated_users

	users_json_read_all || return 1
	if ! jq --exit-status --arg id "$user_id" 'any(.[]; (.id | tostring) == $id)' <<<"$USERS_JSON_DATA" >/dev/null; then
		USERS_REPOSITORY_DELETED=false
		return 0
	fi
	updated_users=$(jq --compact-output --arg id "$user_id" '[.[] | select((.id | tostring) != $id)]' <<<"$USERS_JSON_DATA") || return 1
	users_json_write_all "$updated_users" || return 1
	USERS_REPOSITORY_DELETED=true
}
