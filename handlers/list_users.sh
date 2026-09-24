#!/usr/bin/env bash

# shellcheck source=users-data.sh
source "$ROOT_DIR/handlers/users-data.sh"

handle_list_users() {
	users_read_all || return 1
	response_set_structured 200 "$USERS_DATA"
}
