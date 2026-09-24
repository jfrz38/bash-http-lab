#!/usr/bin/env bash

# shellcheck source=users-data.sh
source "$ROOT_DIR/handlers/users-data.sh"

handle_delete_user() {
	local user_id=${REQUEST_PATH_PARAMS[userId]}
	local matches updated_users response

	users_read_all || return 1
	matches=$(jq --arg id "$user_id" '[.[] | select((.id | tostring) == $id)] | length' <<<"$USERS_DATA") || return 1
	if ((matches == 0)); then
		set_error_response 404
		return
	fi
	updated_users=$(jq --compact-output --arg id "$user_id" '[.[] | select((.id | tostring) != $id)]' <<<"$USERS_DATA") || return 1
	users_write_all "$updated_users" || return 1
	response=$(jq --compact-output --null-input --arg id "$user_id" '{deleted: true, id: $id}') || return 1
	response_set_structured 200 "$response"
}
