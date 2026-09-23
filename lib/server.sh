#!/usr/bin/env bash

start_server() {
	local host=$1
	local port=$2
	local entrypoint=$3
	local openapi_file=$4
	local connection_command

	printf -v connection_command 'bash %q __handle-connection %q' "$entrypoint" "$openapi_file"
	exec socat -T "$REQUEST_TIMEOUT_SECONDS" \
		"TCP-LISTEN:${port},bind=${host},reuseaddr,fork" \
		"EXEC:${connection_command},nofork"
}

handle_connection() {
	local openapi_file=$1
	local handlers_dir=$2
	local parse_status route_status handler_status

	response_reset
	if ! openapi_load_routes "$openapi_file"; then
		printf '%s\n' "$OPENAPI_ERROR" >&2
		set_error_response 500
		write_response
		return
	fi

	parse_request
	parse_status=$?

	case $parse_status in
	0)
		route_resolve "$REQUEST_METHOD" "$REQUEST_PATH"
		route_status=$?
		case $route_status in
		0)
			invoke_route_handler "$handlers_dir" "$ROUTE_OPERATION_ID"
			handler_status=$?
			case $handler_status in
			0) ;;
			"$ROUTE_HANDLER_MISSING") set_error_response 501 ;;
			*)
				printf 'Handler failed for operation %s.\n' "$ROUTE_OPERATION_ID" >&2
				set_error_response 500
				;;
			esac
			;;
		"$ROUTE_NOT_FOUND") set_error_response 404 ;;
		"$ROUTE_METHOD_NOT_ALLOWED")
			set_error_response 405
			response_add_header 'Allow' "$ROUTE_ALLOWED_METHODS"
			;;
		*)
			printf 'Unexpected router failure: %s.\n' "$route_status" >&2
			set_error_response 500
			;;
		esac
		;;
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
