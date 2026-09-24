#!/usr/bin/env bash

REQUEST_ID=''

request_id_set_response_header() {
	local header header_name
	local -a retained_headers=()

	for header in "${RESPONSE_EXTRA_HEADERS[@]}"; do
		header_name=${header%%:*}
		[[ ${header_name,,} == 'x-request-id' ]] || retained_headers+=("$header")
	done
	RESPONSE_EXTRA_HEADERS=("${retained_headers[@]}")
	response_add_header 'X-Request-Id' "$REQUEST_ID"
}

middleware_request_id_before() {
	local candidate=${REQUEST_HEADERS["x-request-id"]:-}

	if [[ $candidate =~ ^[A-Za-z0-9._-]{1,128}$ ]]; then
		REQUEST_ID=$candidate
	elif [[ -r /proc/sys/kernel/random/uuid ]]; then
		IFS= read -r REQUEST_ID </proc/sys/kernel/random/uuid
	else
		return 1
	fi
	request_id_set_response_header
}

middleware_request_id_after() {
	request_id_set_response_header
}
