#!/usr/bin/env bash

handle_request_context() {
	local body
	body=$(<"$BODY_NORMALIZED_FILE")
	response_set 200 'application/json' \
		"{\"path\":\"${REQUEST_PATH_PARAMS[itemId]}\",\"query\":\"${REQUEST_QUERY_PARAMS[q]}\",\"header\":\"${REQUEST_HEADER_PARAMS['x-trace']}\",\"body\":$body}"
}
