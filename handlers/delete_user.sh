#!/usr/bin/env bash

handle_delete_user() {
	local user_id=${REQUEST_PATH_PARAMS[userId]}
	local response

	users_repository_delete "$user_id" || return 1
	if [[ $USERS_REPOSITORY_DELETED == false ]]; then
		set_error_response 404
		return
	fi
	response=$(jq --compact-output --null-input --arg id "$user_id" '{deleted: true, id: $id}') || return 1
	response_set_structured 200 "$response"
}
