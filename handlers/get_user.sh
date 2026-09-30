#!/usr/bin/env bash

handle_get_user() {
	local user_id=${REQUEST_PATH_PARAMS[userId]}

	users_repository_find_by_id "$user_id" || return 1
	if [[ $USERS_REPOSITORY_FOUND == false ]]; then
		set_error_response 404
		return
	fi
	response_set_structured 200 "$USERS_REPOSITORY_RESULT"
}
