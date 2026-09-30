#!/usr/bin/env bash
# shellcheck disable=SC2034

declare -a MIDDLEWARE_ACTIVE_NAMES=()

middleware_reset() {
	MIDDLEWARE_ACTIVE_NAMES=()
	REQUEST_ID=''
	LOGGING_START_MICROSECONDS=0
}

middleware_hook_name() {
	local middleware_name=$1
	local phase=$2

	middleware_name=${middleware_name//Id/_id}
	MIDDLEWARE_HOOK_NAME="middleware_${middleware_name}_${phase}"
}

middleware_run_before() {
	local operation_id=$1
	local index middleware_name

	for ((index = 0; index < ${#OPENAPI_MIDDLEWARE_NAMES[@]}; index += 1)); do
		[[ ${OPENAPI_MIDDLEWARE_OPERATION_IDS[$index]} == "$operation_id" ]] || continue
		middleware_name=${OPENAPI_MIDDLEWARE_NAMES[$index]}
		middleware_hook_name "$middleware_name" before
		if ! "$MIDDLEWARE_HOOK_NAME"; then
			printf 'Middleware %s failed before operation %s.\n' "$middleware_name" "$operation_id" >&2
			return 1
		fi
		MIDDLEWARE_ACTIVE_NAMES+=("$middleware_name")
	done
}

middleware_run_after() {
	local operation_id=$1
	local middleware_name status=0

	for middleware_name in "${MIDDLEWARE_ACTIVE_NAMES[@]}"; do
		middleware_hook_name "$middleware_name" after
		if ! "$MIDDLEWARE_HOOK_NAME"; then
			printf 'Middleware %s failed after operation %s.\n' "$middleware_name" "$operation_id" >&2
			status=1
		fi
	done
	return "$status"
}
