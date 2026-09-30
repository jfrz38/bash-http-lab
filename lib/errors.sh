#!/usr/bin/env bash

set_error_response() {
	local status=$1

	if ! response_reason_phrase "$status"; then
		status=500
		response_reason_phrase "$status"
	fi
	response_set_structured "$status" "{\"error\":\"$REASON_PHRASE\"}"
}
