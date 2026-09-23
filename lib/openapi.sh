#!/usr/bin/env bash
# shellcheck disable=SC2034

readonly OPENAPI_INVALID=20
readonly OPENAPI_UNSUPPORTED=21

declare -a OPENAPI_ROUTE_METHODS=()
declare -a OPENAPI_ROUTE_PATHS=()
declare -a OPENAPI_ROUTE_OPERATION_IDS=()
OPENAPI_ERROR=''
OPENAPI_PATH_SIGNATURE=''

openapi_reset() {
	OPENAPI_ROUTE_METHODS=()
	OPENAPI_ROUTE_PATHS=()
	OPENAPI_ROUTE_OPERATION_IDS=()
	OPENAPI_ERROR=''
}

openapi_fail() {
	OPENAPI_ERROR=$1
	return "$2"
}

openapi_is_method_key() {
	case $1 in
	get | put | post | delete | options | head | patch | trace) return 0 ;;
	*) return 1 ;;
	esac
}

openapi_validate_path_template() {
	local path=$1
	local remainder segment parameter_name signature
	local -A seen_parameters=()

	if [[ $path != /* || $path == *'?'* || $path == *'#'* || $path =~ [[:cntrl:][:space:]] ]]; then
		openapi_fail "Invalid OpenAPI path template: $path" "$OPENAPI_INVALID"
		return
	fi

	signature=$path
	remainder=${path#/}
	while true; do
		if [[ $remainder == */* ]]; then
			segment=${remainder%%/*}
			remainder=${remainder#*/}
		else
			segment=$remainder
			remainder=''
		fi

		if [[ $segment == *'{'* || $segment == *'}'* ]]; then
			if [[ ! $segment =~ ^\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
				openapi_fail "Unsupported partial path parameter in: $path" "$OPENAPI_UNSUPPORTED"
				return
			fi
			parameter_name=${BASH_REMATCH[1]}
			if [[ -v "seen_parameters[$parameter_name]" ]]; then
				openapi_fail "Duplicate path parameter '$parameter_name' in: $path" "$OPENAPI_INVALID"
				return
			fi
			seen_parameters["$parameter_name"]=1
			signature=${signature//\{$parameter_name\}/\{\}}
		fi

		[[ -z $remainder ]] && break
	done

	OPENAPI_PATH_SIGNATURE=$signature
}

openapi_load_routes() {
	local file=$1
	local version paths_tag path_records key_records
	local path value_tag key operation_tag operation_id responses_tag method signature
	local -A seen_operation_ids=()
	local -A signature_paths=()

	openapi_reset
	if [[ ! -f $file || ! -r $file ]]; then
		openapi_fail "OpenAPI file is not readable: $file" "$OPENAPI_INVALID"
		return
	fi

	version=$(yq eval '.openapi // ""' "$file" </dev/null 2>/dev/null) || {
		openapi_fail "Unable to parse OpenAPI document: $file" "$OPENAPI_INVALID"
		return
	}
	if [[ -z $version ]]; then
		openapi_fail 'OpenAPI document must declare an openapi version.' "$OPENAPI_INVALID"
		return
	fi
	if [[ ! $version =~ ^3\.0\.[0-9]+$ ]]; then
		openapi_fail "Unsupported OpenAPI version: $version" "$OPENAPI_UNSUPPORTED"
		return
	fi

	paths_tag=$(yq eval '.paths | tag' "$file" </dev/null 2>/dev/null) || {
		openapi_fail 'Unable to read OpenAPI paths.' "$OPENAPI_INVALID"
		return
	}
	if [[ $paths_tag != '!!map' ]]; then
		openapi_fail 'OpenAPI paths must be a mapping.' "$OPENAPI_INVALID"
		return
	fi

	path_records=$(yq eval '.paths | keys | .[]' "$file" </dev/null 2>/dev/null) || {
		openapi_fail 'Unable to read OpenAPI path definitions.' "$OPENAPI_INVALID"
		return
	}
	while IFS= read -r path; do
		[[ -z $path ]] && continue
		value_tag=$(OPENAPI_PATH=$path yq eval '.paths[strenv(OPENAPI_PATH)] | tag' "$file" </dev/null 2>/dev/null) || {
			openapi_fail "Unable to read OpenAPI path item: $path" "$OPENAPI_INVALID"
			return
		}
		if [[ $value_tag != '!!map' ]]; then
			openapi_fail "OpenAPI path item must be a mapping: $path" "$OPENAPI_INVALID"
			return
		fi
		openapi_validate_path_template "$path" || return $?
		signature=$OPENAPI_PATH_SIGNATURE
		if [[ -v "signature_paths[$signature]" && ${signature_paths[$signature]} != "$path" ]]; then
			openapi_fail "Ambiguous OpenAPI path templates: ${signature_paths[$signature]} and $path" "$OPENAPI_INVALID"
			return
		fi
		signature_paths["$signature"]=$path
	done <<<"$path_records"

	while IFS= read -r path; do
		[[ -z $path ]] && continue
		key_records=$(OPENAPI_PATH=$path yq eval '.paths[strenv(OPENAPI_PATH)] | keys | .[]' "$file" </dev/null 2>/dev/null) || {
			openapi_fail "Unable to read OpenAPI path item fields: $path" "$OPENAPI_INVALID"
			return
		}
		while IFS= read -r key; do
			[[ -z $key ]] && continue
			if ! openapi_is_method_key "$key"; then
				case $key in
				parameters | summary | description | servers | x-*) continue ;;
				\$ref)
					openapi_fail "OpenAPI path references are not supported: $path" "$OPENAPI_UNSUPPORTED"
					return
					;;
				*)
					openapi_fail "Unsupported OpenAPI path item field '$key' in: $path" "$OPENAPI_UNSUPPORTED"
					return
					;;
				esac
			fi
			operation_tag=$(OPENAPI_PATH=$path OPENAPI_KEY=$key yq eval '.paths[strenv(OPENAPI_PATH)][strenv(OPENAPI_KEY)] | tag' "$file" </dev/null 2>/dev/null) || {
				openapi_fail "Unable to read OpenAPI operation: $key $path" "$OPENAPI_INVALID"
				return
			}
			operation_id=$(OPENAPI_PATH=$path OPENAPI_KEY=$key yq eval '.paths[strenv(OPENAPI_PATH)][strenv(OPENAPI_KEY)].operationId // ""' "$file" </dev/null 2>/dev/null) || {
				openapi_fail "Unable to read operationId for: $key $path" "$OPENAPI_INVALID"
				return
			}
			responses_tag=$(OPENAPI_PATH=$path OPENAPI_KEY=$key yq eval '.paths[strenv(OPENAPI_PATH)][strenv(OPENAPI_KEY)].responses | tag' "$file" </dev/null 2>/dev/null) || {
				openapi_fail "Unable to read responses for: $key $path" "$OPENAPI_INVALID"
				return
			}
			if [[ $operation_tag != '!!map' ]]; then
				openapi_fail "OpenAPI operation '$key $path' must be a mapping." "$OPENAPI_INVALID"
				return
			fi
			if [[ ! $operation_id =~ ^[a-z][a-z0-9_]*$ ]]; then
				openapi_fail "Invalid operationId for $key $path: $operation_id" "$OPENAPI_INVALID"
				return
			fi
			if [[ -v "seen_operation_ids[$operation_id]" ]]; then
				openapi_fail "Duplicate operationId: $operation_id" "$OPENAPI_INVALID"
				return
			fi
			if [[ $responses_tag != '!!map' ]]; then
				openapi_fail "OpenAPI operation '$key $path' must define responses." "$OPENAPI_INVALID"
				return
			fi
			seen_operation_ids["$operation_id"]=1
			method=${key^^}
			OPENAPI_ROUTE_METHODS+=("$method")
			OPENAPI_ROUTE_PATHS+=("$path")
			OPENAPI_ROUTE_OPERATION_IDS+=("$operation_id")
		done <<<"$key_records"
	done <<<"$path_records"
}

openapi_print_routes() {
	local index

	printf '%-8s %-32s %s\n' 'METHOD' 'PATH' 'OPERATION'
	for ((index = 0; index < ${#OPENAPI_ROUTE_METHODS[@]}; index += 1)); do
		printf '%-8s %-32s %s\n' \
			"${OPENAPI_ROUTE_METHODS[$index]}" \
			"${OPENAPI_ROUTE_PATHS[$index]}" \
			"${OPENAPI_ROUTE_OPERATION_IDS[$index]}"
	done
}
