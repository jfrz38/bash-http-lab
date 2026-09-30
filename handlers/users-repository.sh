#!/usr/bin/env bash

users_repository_load() {
	local backend=${BASH_HTTP_USERS_BACKEND:-json}
	local adapter
	local required_function

	case $backend in
	json | sqlite) adapter="$ROOT_DIR/handlers/persistence/users-$backend.sh" ;;
	*)
		printf 'Unsupported users backend: %s. Expected json or sqlite.\n' "$backend" >&2
		return 1
		;;
	esac

	# shellcheck source=/dev/null
	source "$adapter" || return 1
	for required_function in \
		users_repository_initialize \
		users_repository_list \
		users_repository_find_by_id \
		users_repository_create \
		users_repository_delete; do
		if ! declare -F "$required_function" >/dev/null; then
			printf 'Users backend %s does not implement %s.\n' "$backend" "$required_function" >&2
			return 1
		fi
	done
}
