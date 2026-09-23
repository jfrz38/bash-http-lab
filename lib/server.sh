#!/usr/bin/env bash

start_server() {
	local host=$1
	local port=$2
	local entrypoint=$3
	local connection_command

	printf -v connection_command 'bash %q __handle-connection' "$entrypoint"
	exec socat -T "$REQUEST_TIMEOUT_SECONDS" \
		"TCP-LISTEN:${port},bind=${host},reuseaddr,fork" \
		"EXEC:${connection_command},nofork"
}

route_request() {
	if [[ $REQUEST_PATH != '/health' ]]; then
		set_error_response 404
	elif [[ $REQUEST_METHOD != 'GET' ]]; then
		set_error_response 405
		response_add_header 'Allow' 'GET'
	elif ! handle_health; then
		printf 'Health handler failed.\n' >&2
		set_error_response 500
	fi
}

handle_connection() {
	local parse_status

	response_reset
	parse_request
	parse_status=$?

	case $parse_status in
	0) route_request ;;
	"$REQUEST_PARSE_BAD_REQUEST") set_error_response 400 ;;
	"$REQUEST_PARSE_NOT_IMPLEMENTED") set_error_response 501 ;;
	"$REQUEST_PARSE_TIMEOUT")
		printf 'Connection timed out before a complete request was received.\n' >&2
		return 0
		;;
	*)
		printf 'Unexpected request parser failure: %s.\n' "$parse_status" >&2
		set_error_response 500
		;;
	esac

	if ! write_response; then
		printf 'Unable to serialize HTTP response.\n' >&2
		return 1
	fi
}
