#!/usr/bin/env bash

set_error_response() {
	local status=$1

	if ! response_reason_phrase "$status"; then
		status=500
		response_reason_phrase "$status"
	fi
	response_set "$status" 'application/json' "{\"error\":\"$REASON_PHRASE\"}"
}
