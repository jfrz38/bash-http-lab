#!/usr/bin/env bash

LOGGING_START_MICROSECONDS=0

logging_now_microseconds() {
	LOGGING_NOW_MICROSECONDS=${EPOCHREALTIME/./}
}

middleware_logging_before() {
	logging_now_microseconds
	LOGGING_START_MICROSECONDS=$LOGGING_NOW_MICROSECONDS
}

middleware_logging_after() {
	local duration_ms log_record

	logging_now_microseconds
	duration_ms=$(((LOGGING_NOW_MICROSECONDS - LOGGING_START_MICROSECONDS) / 1000))
	log_record=$(jq --compact-output --null-input \
		--arg requestId "$REQUEST_ID" \
		--arg method "$REQUEST_METHOD" \
		--arg path "$REQUEST_PATH" \
		--argjson status "$RESPONSE_STATUS" \
		--argjson durationMs "$duration_ms" \
		'{requestId: $requestId, method: $method, path: $path, status: $status, durationMs: $durationMs}') || return 1
	printf '%s\n' "$log_record" >&2
}
