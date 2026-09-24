#!/usr/bin/env bash

RESPONSE_STATUS=500
RESPONSE_CONTENT_TYPE='application/json'
RESPONSE_BODY=''
declare -a RESPONSE_EXTRA_HEADERS=()

response_reset() {
	RESPONSE_STATUS=500
	RESPONSE_CONTENT_TYPE='application/json'
	RESPONSE_BODY=''
	RESPONSE_EXTRA_HEADERS=()
}

response_set() {
	RESPONSE_STATUS=$1
	RESPONSE_CONTENT_TYPE=$2
	RESPONSE_BODY=$3
}

response_add_header() {
	local name=$1
	local value=$2

	RESPONSE_EXTRA_HEADERS+=("$name: $value")
}

response_reason_phrase() {
	case $1 in
	200) REASON_PHRASE='OK' ;;
	400) REASON_PHRASE='Bad Request' ;;
	404) REASON_PHRASE='Not Found' ;;
	405) REASON_PHRASE='Method Not Allowed' ;;
	413) REASON_PHRASE='Content Too Large' ;;
	415) REASON_PHRASE='Unsupported Media Type' ;;
	500) REASON_PHRASE='Internal Server Error' ;;
	501) REASON_PHRASE='Not Implemented' ;;
	*) return 1 ;;
	esac
}

write_response() {
	local body_length header
	local LC_ALL=C

	if ! response_reason_phrase "$RESPONSE_STATUS"; then
		return 1
	fi
	body_length=${#RESPONSE_BODY}

	printf 'HTTP/1.1 %s %s\r\n' "$RESPONSE_STATUS" "$REASON_PHRASE"
	printf 'Content-Type: %s\r\n' "$RESPONSE_CONTENT_TYPE"
	printf 'Content-Length: %s\r\n' "$body_length"
	printf 'Connection: close\r\n'
	for header in "${RESPONSE_EXTRA_HEADERS[@]}"; do
		printf '%s\r\n' "$header"
	done
	printf '\r\n%s' "$RESPONSE_BODY"
}
