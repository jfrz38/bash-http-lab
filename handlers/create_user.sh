#!/usr/bin/env bash

handle_create_user() {
	users_repository_create "$BODY_NORMALIZED_FILE" || return 1
	response_set_structured 201 "$USERS_REPOSITORY_RESULT"
}
