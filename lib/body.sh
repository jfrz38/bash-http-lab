#!/usr/bin/env bash
# shellcheck disable=SC2034

readonly BODY_BAD_REQUEST=30
readonly BODY_UNSUPPORTED_MEDIA_TYPE=31
readonly BODY_INTERNAL_ERROR=32

BODY_TEMP_DIR=''
BODY_RAW_FILE=''
BODY_NORMALIZED_FILE=''
BODY_MEDIA_TYPE=''
BODY_FORMAT='none'

body_reset() {
	BODY_TEMP_DIR=''
	BODY_RAW_FILE=''
	BODY_NORMALIZED_FILE=''
	BODY_MEDIA_TYPE=''
	BODY_FORMAT='none'
}

body_context_create() {
	body_cleanup
	BODY_TEMP_DIR=$(mktemp -d) || return "$BODY_INTERNAL_ERROR"
	chmod 700 "$BODY_TEMP_DIR" || {
		body_cleanup
		return "$BODY_INTERNAL_ERROR"
	}
	BODY_RAW_FILE="$BODY_TEMP_DIR/raw"
	BODY_NORMALIZED_FILE="$BODY_TEMP_DIR/normalized"
	: >"$BODY_RAW_FILE" || {
		body_cleanup
		return "$BODY_INTERNAL_ERROR"
	}
}

body_cleanup() {
	if [[ -n ${BODY_TEMP_DIR:-} ]]; then
		rm -rf -- "$BODY_TEMP_DIR"
	fi
	body_reset
}

body_parse_media_type() {
	local content_type=$1
	local media_type=${content_type%%;*}
	local parameters parameter name
	local media_type_pattern="^[a-z0-9!#\$%&'*+.^_\`|~-]+/[a-z0-9!#\$%&'*+.^_\`|~-]+$"
	local parameter_pattern="^[[:blank:]]*([a-zA-Z0-9!#\$%&'*+.^_\`|~-]+)[[:blank:]]*=[[:blank:]]*[a-zA-Z0-9!#\$%&'*+.^_\`|~-]+[[:blank:]]*$"
	local -A seen_parameters=()

	media_type=${media_type#"${media_type%%[!$' \t']*}"}
	media_type=${media_type%"${media_type##*[!$' \t']}"}
	media_type=${media_type,,}
	[[ $media_type =~ $media_type_pattern ]] || return "$BODY_BAD_REQUEST"

	if [[ $content_type == *';'* ]]; then
		parameters=${content_type#*;}
		[[ -n $parameters && $parameters != *';' ]] || return "$BODY_BAD_REQUEST"
		while true; do
			if [[ $parameters == *';'* ]]; then
				parameter=${parameters%%;*}
				parameters=${parameters#*;}
			else
				parameter=$parameters
				parameters=''
			fi
			[[ $parameter =~ $parameter_pattern ]] || return "$BODY_BAD_REQUEST"
			name=${BASH_REMATCH[1],,}
			[[ ! -v "seen_parameters[$name]" ]] || return "$BODY_BAD_REQUEST"
			seen_parameters["$name"]=1
			[[ -n $parameters ]] || break
		done
	fi
	BODY_MEDIA_TYPE=$media_type
}

body_normalize() {
	local content_type converted_yaml

	BODY_MEDIA_TYPE=''
	BODY_FORMAT='none'
	: >"$BODY_NORMALIZED_FILE" || return "$BODY_INTERNAL_ERROR"
	if ((REQUEST_CONTENT_LENGTH == 0)); then
		return 0
	fi
	[[ -v 'REQUEST_HEADERS[content-type]' ]] || return "$BODY_BAD_REQUEST"
	content_type=${REQUEST_HEADERS['content-type']}
	body_parse_media_type "$content_type" || return $?

	case $BODY_MEDIA_TYPE in
	application/json)
		require_command jq || return "$BODY_INTERNAL_ERROR"
		if ! jq --compact-output --slurp 'if length == 1 then .[0] else error("expected exactly one JSON value") end' "$BODY_RAW_FILE" >"$BODY_NORMALIZED_FILE" 2>/dev/null; then
			return "$BODY_BAD_REQUEST"
		fi
		BODY_FORMAT='json'
		;;
	application/yaml | application/x-yaml | text/yaml | text/x-yaml)
		require_command jq || return "$BODY_INTERNAL_ERROR"
		converted_yaml="$BODY_TEMP_DIR/yaml-json"
		if ! yq eval --output-format=json --indent=0 '.' "$BODY_RAW_FILE" >"$converted_yaml" 2>/dev/null; then
			return "$BODY_BAD_REQUEST"
		fi
		if ! jq --compact-output --slurp 'if length == 1 then .[0] else error("expected exactly one YAML document") end' "$converted_yaml" >"$BODY_NORMALIZED_FILE" 2>/dev/null; then
			return "$BODY_BAD_REQUEST"
		fi
		BODY_FORMAT='json'
		;;
	text/plain)
		if ! cp -- "$BODY_RAW_FILE" "$BODY_NORMALIZED_FILE"; then
			return "$BODY_INTERNAL_ERROR"
		fi
		BODY_FORMAT='text'
		;;
	*) return "$BODY_UNSUPPORTED_MEDIA_TYPE" ;;
	esac
}
