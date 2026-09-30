#!/usr/bin/env bash
# shellcheck disable=SC2034

readonly PARAMS_BAD_REQUEST=20

declare -A REQUEST_PATH_PARAMS=()
declare -A REQUEST_QUERY_PARAMS=()
declare -A REQUEST_HEADER_PARAMS=()
REQUEST_PARAM_VALUE=''

params_reset() {
	REQUEST_PATH_PARAMS=()
	REQUEST_QUERY_PARAMS=()
	REQUEST_HEADER_PARAMS=()
	REQUEST_PARAM_VALUE=''
}

decode_query_component() {
	local encoded=$1
	local decoded='' prefix hex byte

	encoded=${encoded//+/ }
	while [[ $encoded == *%* ]]; do
		prefix=${encoded%%\%*}
		encoded=${encoded#*%}
		if [[ ! $encoded =~ ^([0-9A-Fa-f]{2})(.*)$ ]]; then
			return "$PARAMS_BAD_REQUEST"
		fi
		hex=${BASH_REMATCH[1]}
		encoded=${BASH_REMATCH[2]}
		[[ $hex != '00' ]] || return "$PARAMS_BAD_REQUEST"
		printf -v byte '%b' "\\x$hex"
		decoded+="$prefix$byte"
	done
	DECODED_QUERY_COMPONENT=$decoded$encoded
}

parse_query_params() {
	local query=$1
	local pair encoded_name encoded_value name value
	local -a pairs=()
	local LC_ALL=C

	[[ -n $query ]] || return 0
	[[ $query != '&'* && $query != *'&' && $query != *'&&'* ]] || return "$PARAMS_BAD_REQUEST"
	IFS='&' read -r -a pairs <<<"$query"
	for pair in "${pairs[@]}"; do
		[[ -n $pair ]] || return "$PARAMS_BAD_REQUEST"
		encoded_name=${pair%%=*}
		if [[ $pair == *=* ]]; then
			encoded_value=${pair#*=}
		else
			encoded_value=''
		fi
		decode_query_component "$encoded_name" || return "$PARAMS_BAD_REQUEST"
		name=$DECODED_QUERY_COMPONENT
		decode_query_component "$encoded_value" || return "$PARAMS_BAD_REQUEST"
		value=$DECODED_QUERY_COMPONENT
		[[ -n $name ]] || return "$PARAMS_BAD_REQUEST"
		[[ $name =~ ^[A-Za-z0-9_.~-]+$ ]] || return "$PARAMS_BAD_REQUEST"
		[[ ! -v "REQUEST_QUERY_PARAMS[$name]" ]] || return "$PARAMS_BAD_REQUEST"
		REQUEST_QUERY_PARAMS["$name"]=$value
	done
}

params_build() {
	local name

	params_reset
	for name in "${!ROUTE_PATH_PARAMS[@]}"; do
		REQUEST_PATH_PARAMS["$name"]=${ROUTE_PATH_PARAMS[$name]}
	done
	for name in "${!REQUEST_HEADERS[@]}"; do
		REQUEST_HEADER_PARAMS["$name"]=${REQUEST_HEADERS[$name]}
	done
	parse_query_params "$REQUEST_QUERY_STRING"
}

request_param_get() {
	local map_name=$1
	local key=$2
	local -n params=$map_name

	[[ -n $key ]] || return 1
	[[ -v "params[$key]" ]] || return 1
	REQUEST_PARAM_VALUE=${params[$key]}
}

request_path_param() {
	request_param_get REQUEST_PATH_PARAMS "$1"
}

request_query_param() {
	request_param_get REQUEST_QUERY_PARAMS "$1"
}

request_header_param() {
	request_param_get REQUEST_HEADER_PARAMS "${1,,}"
}
