#!/usr/bin/env bash

handle_list_users() {
	users_repository_list || return 1
	response_set_structured 200 "$USERS_REPOSITORY_RESULT"
}
