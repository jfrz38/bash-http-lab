#!/usr/bin/env bash

# shellcheck source=users-data.sh
source "$ROOT_DIR/handlers/users-data.sh"

handle_get_user() {
	local user_id=${REQUEST_PATH_PARAMS[userId]}
	local user

	users_read_all || return 1
	user=$(jq --compact-output --arg id "$user_id" '.[] | select((.id | tostring) == $id)' <<<"$USERS_DATA") || return 1
	if [[ -z $user ]]; then
		set_error_response 404
		return
	fi
	response_set_structured 200 "$user"
}
