#!/usr/bin/env bash

readonly VALIDATION_BAD_REQUEST=50
readonly VALIDATION_UNSUPPORTED_MEDIA_TYPE=51
readonly VALIDATION_INTERNAL_ERROR=52

validation_schema_accepts_parameter() {
	local schema=$1
	local raw_value=$2

	jq --exit-status --null-input \
		--argjson schema "$schema" \
		--arg raw "$raw_value" '
		def value:
			if $schema.type == "string" then $raw
			elif $schema.type == "boolean" then
				if $raw == "true" then true elif $raw == "false" then false else null end
			else try ($raw | fromjson) catch null end;
		def type_matches($value):
			if $schema.type == "string" then ($value | type) == "string"
			elif $schema.type == "integer" then ($value | type) == "number" and ($value | floor) == $value
			elif $schema.type == "number" then ($value | type) == "number"
			elif $schema.type == "boolean" then ($value | type) == "boolean"
			else false end;
		value as $value |
		type_matches($value) and
		(($schema | has("enum") | not) or any($schema.enum[]; . == $value)) and
		(($schema | has("minimum") | not) or $value >= $schema.minimum) and
		(($schema | has("maximum") | not) or $value <= $schema.maximum) and
		(($schema | has("minLength") | not) or ($value | length) >= $schema.minLength) and
		(($schema | has("maxLength") | not) or ($value | length) <= $schema.maxLength)
	' >/dev/null 2>&1
}

validation_schema_accepts_body() {
	local schema=$1
	local value_option=$2
	local value_file=$3
	local body_format=$4

	jq --exit-status --null-input \
		--argjson schema "$schema" \
		--arg body_format "$body_format" \
		"$value_option" value "$value_file" '
		def type_matches($value):
			if $schema.type == "string" then ($value | type) == "string"
			elif $schema.type == "integer" then ($value | type) == "number" and ($value | floor) == $value
			elif $schema.type == "number" then ($value | type) == "number"
			elif $schema.type == "boolean" then ($value | type) == "boolean"
			elif $schema.type == "object" then ($value | type) == "object"
			elif $schema.type == "array" then ($value | type) == "array"
			else false end;
		(if $body_format == "text" then $value else $value[0] end) as $value |
		type_matches($value) and
		(($schema | has("enum") | not) or any($schema.enum[]; . == $value)) and
		(($schema | has("minimum") | not) or $value >= $schema.minimum) and
		(($schema | has("maximum") | not) or $value <= $schema.maximum) and
		(($schema | has("minLength") | not) or ($value | length) >= $schema.minLength) and
		(($schema | has("maxLength") | not) or ($value | length) <= $schema.maxLength)
	' >/dev/null 2>&1
}

validation_get_parameter() {
	local location=$1
	local name=$2

	VALIDATION_PARAMETER_PRESENT=false
	VALIDATION_PARAMETER_VALUE=''
	case $location in
	path)
		[[ -v "REQUEST_PATH_PARAMS[$name]" ]] || return 0
		VALIDATION_PARAMETER_VALUE=${REQUEST_PATH_PARAMS[$name]}
		;;
	query)
		[[ -v "REQUEST_QUERY_PARAMS[$name]" ]] || return 0
		VALIDATION_PARAMETER_VALUE=${REQUEST_QUERY_PARAMS[$name]}
		;;
	header)
		[[ -v "REQUEST_HEADER_PARAMS[$name]" ]] || return 0
		VALIDATION_PARAMETER_VALUE=${REQUEST_HEADER_PARAMS[$name]}
		;;
	esac
	VALIDATION_PARAMETER_PRESENT=true
}

validation_validate_request() {
	local operation_id=$1
	local index location name required schema value operation_id_candidate
	local has_validation=0 body_declared=0 body_required=false body_schema=''
	local body_value_option='--slurpfile'

	for operation_id_candidate in "${OPENAPI_PARAMETER_OPERATION_IDS[@]}" "${OPENAPI_BODY_OPERATION_IDS[@]}"; do
		if [[ $operation_id_candidate == "$operation_id" ]]; then
			has_validation=1
			break
		fi
	done
	((has_validation == 0)) || require_command jq || return "$VALIDATION_INTERNAL_ERROR"

	for ((index = 0; index < ${#OPENAPI_PARAMETER_OPERATION_IDS[@]}; index += 1)); do
		[[ ${OPENAPI_PARAMETER_OPERATION_IDS[$index]} == "$operation_id" ]] || continue
		location=${OPENAPI_PARAMETER_LOCATIONS[$index]}
		name=${OPENAPI_PARAMETER_NAMES[$index]}
		required=${OPENAPI_PARAMETER_REQUIRED[$index]}
		schema=${OPENAPI_PARAMETER_SCHEMAS[$index]}
		validation_get_parameter "$location" "$name"
		if [[ $VALIDATION_PARAMETER_PRESENT == 'false' ]]; then
			[[ $required == 'false' ]] || return "$VALIDATION_BAD_REQUEST"
			continue
		fi
		value=$VALIDATION_PARAMETER_VALUE
		validation_schema_accepts_parameter "$schema" "$value" || return "$VALIDATION_BAD_REQUEST"
	done

	for ((index = 0; index < ${#OPENAPI_BODY_OPERATION_IDS[@]}; index += 1)); do
		[[ ${OPENAPI_BODY_OPERATION_IDS[$index]} == "$operation_id" ]] || continue
		body_declared=1
		body_required=${OPENAPI_BODY_REQUIRED[$index]}
		if [[ ${OPENAPI_BODY_MEDIA_TYPES[$index]} == "$BODY_MEDIA_TYPE" ]]; then
			body_schema=${OPENAPI_BODY_SCHEMAS[$index]}
		fi
	done

	if ((REQUEST_CONTENT_LENGTH == 0)); then
		[[ $body_required == 'false' ]] || return "$VALIDATION_BAD_REQUEST"
		return 0
	fi
	((body_declared == 1)) || return "$VALIDATION_UNSUPPORTED_MEDIA_TYPE"
	[[ -n $body_schema ]] || return "$VALIDATION_UNSUPPORTED_MEDIA_TYPE"

	# BODY_FORMAT is populated by body_normalize_request before validation.
	# shellcheck disable=SC2153
	if [[ $BODY_FORMAT == 'text' ]]; then
		body_value_option='--rawfile'
	fi
	validation_schema_accepts_body "$body_schema" "$body_value_option" "$BODY_NORMALIZED_FILE" "$BODY_FORMAT" || return "$VALIDATION_BAD_REQUEST"
}
