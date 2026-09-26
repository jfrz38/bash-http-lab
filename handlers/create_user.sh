#!/usr/bin/env bash

# shellcheck source=users-data.sh
source "$ROOT_DIR/handlers/users-data.sh"

handle_create_user() {
	local next_id user updated_users

	users_read_all || return 1
	next_id=$(jq '[.[].id | tonumber?] | max // 0 | . + 1' <<<"$USERS_DATA") || return 1
	user=$(jq --compact-output --argjson id "$next_id" '. + {id: $id}' "$BODY_NORMALIZED_FILE") || return 1
	updated_users=$(jq --compact-output --argjson user "$user" '. + [$user]' <<<"$USERS_DATA") || return 1
	users_write_all "$updated_users" || return 1
	response_set_structured 201 "$user"
}
