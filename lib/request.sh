#!/usr/bin/env bash
# shellcheck disable=SC2034

readonly REQUEST_PARSE_BAD_REQUEST=10
readonly REQUEST_PARSE_NOT_IMPLEMENTED=11
readonly REQUEST_PARSE_TIMEOUT=12

readonly REQUEST_LINE_LIMIT=8192
readonly REQUEST_HEADER_LINE_LIMIT=8192
readonly REQUEST_HEADER_COUNT_LIMIT=100
readonly REQUEST_HEADER_BYTES_LIMIT=65536
readonly REQUEST_TIMEOUT_SECONDS=10

# Request state is populated here and consumed by later lifecycle modules.
REQUEST_METHOD=''
REQUEST_TARGET=''
REQUEST_PATH=''
REQUEST_QUERY_STRING=''
REQUEST_HTTP_VERSION=''
declare -A REQUEST_HEADERS=()

request_reset() {
	REQUEST_METHOD=''
	REQUEST_TARGET=''
	REQUEST_PATH=''
	REQUEST_QUERY_STRING=''
	REQUEST_HTTP_VERSION=''
	REQUEST_HEADERS=()
}

read_crlf_line() {
	local limit=$1
	local read_status
	local LC_ALL=C

	HTTP_LINE=''
	IFS= read -r -t "$REQUEST_TIMEOUT_SECONDS" HTTP_LINE
	read_status=$?

	if ((read_status != 0)); then
		if ((read_status > 128)); then
			return "$REQUEST_PARSE_TIMEOUT"
		fi
		return "$REQUEST_PARSE_BAD_REQUEST"
	fi

	if ((${#HTTP_LINE} == 0)) || [[ $HTTP_LINE != *$'\r' ]]; then
		return "$REQUEST_PARSE_BAD_REQUEST"
	fi

	HTTP_LINE=${HTTP_LINE%$'\r'}
	if ((${#HTTP_LINE} > limit)); then
		return "$REQUEST_PARSE_BAD_REQUEST"
	fi
}

parse_request_line() {
	local line=$1
	local request_line_pattern='^([^[:space:]]+) ([^[:space:]]+) (HTTP/1\.1)$'
	local method_pattern="^[A-Z0-9!#\$%&'*+.^_\`|~-]+$"

	if [[ ! $line =~ $request_line_pattern ]]; then
		return "$REQUEST_PARSE_BAD_REQUEST"
	fi

	REQUEST_METHOD=${BASH_REMATCH[1]}
	REQUEST_TARGET=${BASH_REMATCH[2]}
	REQUEST_HTTP_VERSION=${BASH_REMATCH[3]}

	if [[ ! $REQUEST_METHOD =~ $method_pattern ]] || [[ $REQUEST_TARGET != /* ]] || [[ $REQUEST_TARGET =~ [[:cntrl:]] ]]; then
		return "$REQUEST_PARSE_BAD_REQUEST"
	fi

	REQUEST_PATH=${REQUEST_TARGET%%\?*}
	if [[ $REQUEST_TARGET == *\?* ]]; then
		REQUEST_QUERY_STRING=${REQUEST_TARGET#*\?}
	fi
}

trim_optional_whitespace() {
	local value=$1

	value=${value#"${value%%[!$' \t']*}"}
	value=${value%"${value##*[!$' \t']}"}
	TRIMMED_VALUE=$value
}

parse_header_line() {
	local line=$1
	local name value normalized_name control_check
	local header_name_pattern="^[A-Za-z0-9!#\$%&'*+.^_\`|~-]+$"

	if [[ $line == ' '* || $line == $'\t'* || $line != *:* ]]; then
		return "$REQUEST_PARSE_BAD_REQUEST"
	fi

	name=${line%%:*}
	value=${line#*:}
	if [[ ! $name =~ $header_name_pattern ]]; then
		return "$REQUEST_PARSE_BAD_REQUEST"
	fi

	trim_optional_whitespace "$value"
	value=$TRIMMED_VALUE
	control_check=${value//$'\t'/}
	if [[ $control_check =~ [[:cntrl:]] ]]; then
		return "$REQUEST_PARSE_BAD_REQUEST"
	fi

	normalized_name=${name,,}
	if [[ -v "REQUEST_HEADERS[$normalized_name]" ]]; then
		return "$REQUEST_PARSE_BAD_REQUEST"
	fi
	REQUEST_HEADERS["$normalized_name"]=$value
}

validate_request_framing() {
	local has_content_length=0
	local has_transfer_encoding=0
	local content_length=''

	if [[ -v 'REQUEST_HEADERS[content-length]' ]]; then
		has_content_length=1
		content_length=${REQUEST_HEADERS["content-length"]}
	fi
	if [[ -v 'REQUEST_HEADERS[transfer-encoding]' ]]; then
		has_transfer_encoding=1
	fi

	if ((has_content_length && has_transfer_encoding)); then
		return "$REQUEST_PARSE_BAD_REQUEST"
	fi
	if ((has_transfer_encoding)); then
		return "$REQUEST_PARSE_NOT_IMPLEMENTED"
	fi
	if ((has_content_length)); then
		if [[ ! $content_length =~ ^[0-9]+$ ]]; then
			return "$REQUEST_PARSE_BAD_REQUEST"
		fi
		if [[ ! $content_length =~ ^0+$ ]]; then
			return "$REQUEST_PARSE_NOT_IMPLEMENTED"
		fi
	fi
}

parse_request() {
	local parse_status header_count=0 header_bytes=0
	local LC_ALL=C

	request_reset

	read_crlf_line "$REQUEST_LINE_LIMIT"
	parse_status=$?
	if ((parse_status != 0)); then
		return "$parse_status"
	fi
	parse_request_line "$HTTP_LINE" || return "$REQUEST_PARSE_BAD_REQUEST"

	while true; do
		read_crlf_line "$REQUEST_HEADER_LINE_LIMIT"
		parse_status=$?
		if ((parse_status != 0)); then
			return "$parse_status"
		fi

		((header_bytes += ${#HTTP_LINE} + 2))
		if ((header_bytes > REQUEST_HEADER_BYTES_LIMIT)); then
			return "$REQUEST_PARSE_BAD_REQUEST"
		fi
		if [[ -z $HTTP_LINE ]]; then
			break
		fi

		((header_count += 1))
		if ((header_count > REQUEST_HEADER_COUNT_LIMIT)); then
			return "$REQUEST_PARSE_BAD_REQUEST"
		fi
		parse_header_line "$HTTP_LINE" || return "$REQUEST_PARSE_BAD_REQUEST"
	done

	validate_request_framing
}
