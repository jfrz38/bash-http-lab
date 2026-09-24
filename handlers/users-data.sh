#!/usr/bin/env bash
# shellcheck disable=SC2034

users_data_path() {
	USERS_DATA_FILE=${BASH_HTTP_USERS_FILE:-$ROOT_DIR/data/users.json}
}

users_read_all() {
	users_data_path
	[[ -r $USERS_DATA_FILE ]] || return 1
	USERS_DATA=$(jq --compact-output 'if type == "array" then . else error("users data must be an array") end' "$USERS_DATA_FILE" 2>/dev/null) || return 1
}

users_write_all() {
	local value=$1
	local data_dir temporary_file

	users_data_path
	data_dir=${USERS_DATA_FILE%/*}
	[[ $data_dir != "$USERS_DATA_FILE" && -d $data_dir && -w $data_dir ]] || return 1
	temporary_file=$(mktemp "$data_dir/.users.XXXXXX") || return 1
	if ! jq --compact-output '.' <<<"$value" >"$temporary_file" 2>/dev/null; then
		rm -f "$temporary_file"
		return 1
	fi
	chmod 0644 "$temporary_file" || {
		rm -f "$temporary_file"
		return 1
	}
	if ! mv "$temporary_file" "$USERS_DATA_FILE"; then
		rm -f "$temporary_file"
		return 1
	fi
}
