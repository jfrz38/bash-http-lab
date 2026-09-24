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

prepare_selected_response() {
	local accept=${REQUEST_HEADERS[accept]-}

	if response_prepare "$accept"; then
		return 0
	fi
	printf 'Unable to prepare structured HTTP response.\n' >&2
	set_error_response 500
	response_prepare ''
}

handle_connection() {
	local openapi_file=$1
	local handlers_dir=$2
	local parse_status route_status params_status body_status validation_status handler_status middleware_status

	response_reset
	middleware_reset
	if ! openapi_load_routes "$openapi_file"; then
		printf '%s\n' "$OPENAPI_ERROR" >&2
		set_error_response 500
		response_prepare '' || return 1
		write_response
		return
	fi
	params_reset
	if ! body_context_create; then
		printf 'Unable to create private request body storage.\n' >&2
		set_error_response 500
		response_prepare '' || return 1
		write_response
		return
	fi

	parse_request "$BODY_RAW_FILE"
	parse_status=$?

	case $parse_status in
	0)
		route_resolve "$REQUEST_METHOD" "$REQUEST_PATH"
		route_status=$?
		case $route_status in
		0)
			params_build
			params_status=$?
			if ((params_status != 0)); then
				set_error_response 400
			else
				body_normalize
				body_status=$?
				case $body_status in
				0)
					validation_validate_request "$ROUTE_OPERATION_ID"
					validation_status=$?
					case $validation_status in
					0)
						middleware_run_before "$ROUTE_OPERATION_ID"
						middleware_status=$?
						if ((middleware_status == 0)); then
							invoke_route_handler "$handlers_dir" "$ROUTE_OPERATION_ID"
							handler_status=$?
							case $handler_status in
							0)
								if ! openapi_response_status_is_documented "$ROUTE_OPERATION_ID" "$RESPONSE_STATUS"; then
									printf 'Handler %s selected undocumented response status %s.\n' "$ROUTE_OPERATION_ID" "$RESPONSE_STATUS" >&2
								fi
								;;
							"$ROUTE_HANDLER_MISSING") set_error_response 501 ;;
							*)
								printf 'Handler failed for operation %s.\n' "$ROUTE_OPERATION_ID" >&2
								set_error_response 500
								;;
							esac
						else
							set_error_response 500
						fi
						prepare_selected_response || return 1
						if ! middleware_run_after "$ROUTE_OPERATION_ID"; then
							set_error_response 500
						fi
						;;
					"$VALIDATION_BAD_REQUEST") set_error_response 400 ;;
					"$VALIDATION_UNSUPPORTED_MEDIA_TYPE") set_error_response 415 ;;
					*)
						printf 'Unable to validate request for operation %s.\n' "$ROUTE_OPERATION_ID" >&2
						set_error_response 500
						;;
					esac
					;;
				"$BODY_BAD_REQUEST") set_error_response 400 ;;
				"$BODY_UNSUPPORTED_MEDIA_TYPE") set_error_response 415 ;;
				*)
					printf 'Unable to normalize the request body.\n' >&2
					set_error_response 500
					;;
				esac
			fi
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
	"$REQUEST_PARSE_TOO_LARGE") set_error_response 413 ;;
	"$REQUEST_PARSE_TIMEOUT")
		printf 'Connection timed out before a complete request was received.\n' >&2
		body_cleanup
		return 0
		;;
	*)
		printf 'Unexpected request parser failure: %s.\n' "$parse_status" >&2
		set_error_response 500
		;;
	esac

	if ! prepare_selected_response || ! write_response; then
		printf 'Unable to serialize HTTP response.\n' >&2
		body_cleanup
		return 1
	fi
	body_cleanup
}
