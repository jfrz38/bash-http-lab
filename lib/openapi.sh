#!/usr/bin/env bash
# shellcheck disable=SC2034

readonly OPENAPI_INVALID=20
readonly OPENAPI_UNSUPPORTED=21

declare -a OPENAPI_ROUTE_METHODS=()
declare -a OPENAPI_ROUTE_PATHS=()
declare -a OPENAPI_ROUTE_OPERATION_IDS=()
declare -a OPENAPI_PARAMETER_OPERATION_IDS=()
declare -a OPENAPI_PARAMETER_NAMES=()
declare -a OPENAPI_PARAMETER_LOCATIONS=()
declare -a OPENAPI_PARAMETER_REQUIRED=()
declare -a OPENAPI_PARAMETER_SCHEMAS=()
declare -a OPENAPI_BODY_OPERATION_IDS=()
declare -a OPENAPI_BODY_REQUIRED=()
declare -a OPENAPI_BODY_MEDIA_TYPES=()
declare -a OPENAPI_BODY_SCHEMAS=()
declare -a OPENAPI_MIDDLEWARE_OPERATION_IDS=()
declare -a OPENAPI_MIDDLEWARE_NAMES=()
OPENAPI_ERROR=''
OPENAPI_PATH_SIGNATURE=''
OPENAPI_PARAMETER_KEY=''

openapi_reset() {
	OPENAPI_ROUTE_METHODS=()
	OPENAPI_ROUTE_PATHS=()
	OPENAPI_ROUTE_OPERATION_IDS=()
	OPENAPI_PARAMETER_OPERATION_IDS=()
	OPENAPI_PARAMETER_NAMES=()
	OPENAPI_PARAMETER_LOCATIONS=()
	OPENAPI_PARAMETER_REQUIRED=()
	OPENAPI_PARAMETER_SCHEMAS=()
	OPENAPI_BODY_OPERATION_IDS=()
	OPENAPI_BODY_REQUIRED=()
	OPENAPI_BODY_MEDIA_TYPES=()
	OPENAPI_BODY_SCHEMAS=()
	OPENAPI_MIDDLEWARE_OPERATION_IDS=()
	OPENAPI_MIDDLEWARE_NAMES=()
	OPENAPI_ERROR=''
}

openapi_load_middlewares() {
	local file=$1
	local path=$2
	local method=$3
	local operation_id=$4
	local context="$method $path"
	local middlewares_tag middleware_records middleware_record middleware_name middleware_tag
	local -A seen_middlewares=()

	middlewares_tag=$(OPENAPI_PATH=$path OPENAPI_KEY=$method yq eval '.paths[strenv(OPENAPI_PATH)][strenv(OPENAPI_KEY)].x-middlewares | tag' "$file" </dev/null 2>/dev/null) || return "$OPENAPI_INVALID"
	[[ $middlewares_tag != '!!null' ]] || return 0
	if [[ $middlewares_tag != '!!seq' ]]; then
		openapi_fail "x-middlewares in $context must be a sequence." "$OPENAPI_INVALID"
		return
	fi
	if [[ $(OPENAPI_PATH=$path OPENAPI_KEY=$method yq eval '.paths[strenv(OPENAPI_PATH)][strenv(OPENAPI_KEY)].x-middlewares | length' "$file" </dev/null 2>/dev/null) == '0' ]]; then
		return 0
	fi

	middleware_records=$(OPENAPI_PATH=$path OPENAPI_KEY=$method yq eval --output-format=json --indent=0 '.paths[strenv(OPENAPI_PATH)][strenv(OPENAPI_KEY)].x-middlewares[]' "$file" </dev/null 2>/dev/null) || return "$OPENAPI_INVALID"
	while IFS= read -r middleware_record; do
		middleware_tag=$(yq eval 'tag' - <<<"$middleware_record" 2>/dev/null) || return "$OPENAPI_INVALID"
		if [[ $middleware_tag != '!!str' ]]; then
			openapi_fail "Middleware names in $context must be strings." "$OPENAPI_INVALID"
			return
		fi
		middleware_name=$(yq eval --unwrapScalar '.' - <<<"$middleware_record" 2>/dev/null) || return "$OPENAPI_INVALID"
		case $middleware_name in
		requestId | logging) ;;
		*)
			openapi_fail "Unknown middleware '$middleware_name' in $context." "$OPENAPI_UNSUPPORTED"
			return
			;;
		esac
		if [[ -v "seen_middlewares[$middleware_name]" ]]; then
			openapi_fail "Duplicate middleware '$middleware_name' in $context." "$OPENAPI_INVALID"
			return
		fi
		seen_middlewares["$middleware_name"]=1
		OPENAPI_MIDDLEWARE_OPERATION_IDS+=("$operation_id")
		OPENAPI_MIDDLEWARE_NAMES+=("$middleware_name")
	done <<<"$middleware_records"
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

openapi_validate_schema() {
	local schema=$1
	local context=$2
	local allowed_types=$3
	local schema_tag keys key type type_tag value_tag constraint_value enum_tags

	schema_tag=$(yq eval 'tag' - <<<"$schema" 2>/dev/null) || {
		openapi_fail "Unable to read schema for $context." "$OPENAPI_INVALID"
		return
	}
	if [[ $schema_tag != '!!map' ]]; then
		openapi_fail "Schema for $context must be a mapping." "$OPENAPI_INVALID"
		return
	fi

	keys=$(yq eval 'keys | .[]' - <<<"$schema" 2>/dev/null) || {
		openapi_fail "Unable to read schema fields for $context." "$OPENAPI_INVALID"
		return
	}
	while IFS= read -r key; do
		[[ -z $key ]] && continue
		case $key in
		type | enum | minimum | maximum | minLength | maxLength | description | example) ;;
		*)
			openapi_fail "Unsupported schema field '$key' for $context." "$OPENAPI_UNSUPPORTED"
			return
			;;
		esac
	done <<<"$keys"

	type=$(yq eval '.type // ""' - <<<"$schema" 2>/dev/null) || {
		openapi_fail "Unable to read schema type for $context." "$OPENAPI_INVALID"
		return
	}
	type_tag=$(yq eval '.type | tag' - <<<"$schema" 2>/dev/null) || {
		openapi_fail "Unable to read schema type for $context." "$OPENAPI_INVALID"
		return
	}
	if [[ $type_tag == '!!null' ]]; then
		openapi_fail "Schema for $context must declare a type." "$OPENAPI_INVALID"
		return
	fi
	if [[ $type_tag != '!!str' ]]; then
		openapi_fail "Schema type for $context must be a string." "$OPENAPI_INVALID"
		return
	fi
	if [[ " $allowed_types " != *" $type "* ]]; then
		openapi_fail "Unsupported schema type '$type' for $context." "$OPENAPI_UNSUPPORTED"
		return
	fi

	for key in minimum maximum; do
		if [[ $(yq eval "has(\"$key\")" - <<<"$schema" 2>/dev/null) == 'true' ]]; then
			if [[ $type != 'integer' && $type != 'number' ]]; then
				openapi_fail "Schema field '$key' requires a numeric type for $context." "$OPENAPI_INVALID"
				return
			fi
			value_tag=$(yq eval ".$key | tag" - <<<"$schema" 2>/dev/null) || return "$OPENAPI_INVALID"
			if [[ $value_tag != '!!int' && $value_tag != '!!float' ]]; then
				openapi_fail "Schema field '$key' must be numeric for $context." "$OPENAPI_INVALID"
				return
			fi
		fi
	done

	for key in minLength maxLength; do
		if [[ $(yq eval "has(\"$key\")" - <<<"$schema" 2>/dev/null) == 'true' ]]; then
			if [[ $type != 'string' ]]; then
				openapi_fail "Schema field '$key' requires type string for $context." "$OPENAPI_INVALID"
				return
			fi
			value_tag=$(yq eval ".$key | tag" - <<<"$schema" 2>/dev/null) || return "$OPENAPI_INVALID"
			constraint_value=$(yq eval ".$key" - <<<"$schema" 2>/dev/null) || return "$OPENAPI_INVALID"
			if [[ $value_tag != '!!int' ]] || ((constraint_value < 0)); then
				openapi_fail "Schema field '$key' must be a non-negative integer for $context." "$OPENAPI_INVALID"
				return
			fi
		fi
	done

	if [[ $(yq eval 'has("enum")' - <<<"$schema" 2>/dev/null) == 'true' ]]; then
		value_tag=$(yq eval '.enum | tag' - <<<"$schema" 2>/dev/null) || return "$OPENAPI_INVALID"
		constraint_value=$(yq eval '.enum | length' - <<<"$schema" 2>/dev/null) || return "$OPENAPI_INVALID"
		if [[ $value_tag != '!!seq' ]] || ((constraint_value == 0)); then
			openapi_fail "Schema enum must be a non-empty sequence for $context." "$OPENAPI_INVALID"
			return
		fi
		enum_tags=$(yq eval '.enum[] | tag' - <<<"$schema" 2>/dev/null) || return "$OPENAPI_INVALID"
		while IFS= read -r value_tag; do
			case $type:$value_tag in
			string:!!str | integer:!!int | number:!!int | number:!!float | boolean:!!bool | object:!!map | array:!!seq) ;;
			*)
				openapi_fail "Schema enum value does not match type '$type' for $context." "$OPENAPI_INVALID"
				return
				;;
			esac
		done <<<"$enum_tags"
	fi
}

openapi_parameter_identity() {
	local record=$1
	local context=$2
	local record_tag name location name_tag location_tag

	record_tag=$(yq eval 'tag' - <<<"$record" 2>/dev/null) || return "$OPENAPI_INVALID"
	if [[ $record_tag != '!!map' ]]; then
		openapi_fail "Parameter in $context must be a mapping." "$OPENAPI_INVALID"
		return
	fi
	name=$(yq eval '.name // ""' - <<<"$record" 2>/dev/null) || return "$OPENAPI_INVALID"
	location=$(yq eval '.in // ""' - <<<"$record" 2>/dev/null) || return "$OPENAPI_INVALID"
	name_tag=$(yq eval '.name | tag' - <<<"$record" 2>/dev/null) || return "$OPENAPI_INVALID"
	location_tag=$(yq eval '.in | tag' - <<<"$record" 2>/dev/null) || return "$OPENAPI_INVALID"
	if [[ $name_tag != '!!str' || $location_tag != '!!str' ]]; then
		openapi_fail "Parameter name and location must be strings in $context." "$OPENAPI_INVALID"
		return
	fi
	case $location in
	path | query)
		if [[ ! $name =~ ^[A-Za-z0-9_.~-]+$ ]]; then
			openapi_fail "Invalid $location parameter name '$name' in $context." "$OPENAPI_INVALID"
			return
		fi
		;;
	header)
		if [[ ! $name =~ ^[A-Za-z0-9!#\$%\&\'*+.^_\`\|~-]+$ ]]; then
			openapi_fail "Invalid header parameter name '$name' in $context." "$OPENAPI_INVALID"
			return
		fi
		name=${name,,}
		;;
	*)
		openapi_fail "Unsupported parameter location '$location' in $context." "$OPENAPI_UNSUPPORTED"
		return
		;;
	esac
	OPENAPI_PARAMETER_KEY="$location:$name"
}

openapi_add_parameter() {
	local record=$1
	local context=$2
	local operation_id=$3
	local keys key name location required required_tag schema schema_tag

	keys=$(yq eval 'keys | .[]' - <<<"$record" 2>/dev/null) || return "$OPENAPI_INVALID"
	while IFS= read -r key; do
		[[ -z $key ]] && continue
		case $key in
		name | in | required | schema | description | deprecated | example | examples) ;;
		*)
			openapi_fail "Unsupported parameter field '$key' in $context." "$OPENAPI_UNSUPPORTED"
			return
			;;
		esac
	done <<<"$keys"

	name=$(yq eval '.name' - <<<"$record" 2>/dev/null) || return "$OPENAPI_INVALID"
	location=$(yq eval '.in' - <<<"$record" 2>/dev/null) || return "$OPENAPI_INVALID"
	[[ $location != 'header' ]] || name=${name,,}
	required=$(yq eval '.required // false' - <<<"$record" 2>/dev/null) || return "$OPENAPI_INVALID"
	required_tag=$(yq eval '.required | tag' - <<<"$record" 2>/dev/null) || return "$OPENAPI_INVALID"
	if [[ $required_tag != '!!null' && $required_tag != '!!bool' ]]; then
		openapi_fail "Parameter required flag must be boolean in $context." "$OPENAPI_INVALID"
		return
	fi
	if [[ $location == 'path' && $required != 'true' ]]; then
		openapi_fail "Path parameter '$name' must be required in $context." "$OPENAPI_INVALID"
		return
	fi
	schema_tag=$(yq eval '.schema | tag' - <<<"$record" 2>/dev/null) || return "$OPENAPI_INVALID"
	if [[ $schema_tag == '!!null' ]]; then
		openapi_fail "Parameter '$name' must define an inline schema in $context." "$OPENAPI_INVALID"
		return
	fi
	schema=$(yq eval --output-format=json --indent=0 '.schema' - <<<"$record" 2>/dev/null) || return "$OPENAPI_INVALID"
	openapi_validate_schema "$schema" "parameter '$name' in $context" 'string integer number boolean' || return $?

	OPENAPI_PARAMETER_OPERATION_IDS+=("$operation_id")
	OPENAPI_PARAMETER_NAMES+=("$name")
	OPENAPI_PARAMETER_LOCATIONS+=("$location")
	OPENAPI_PARAMETER_REQUIRED+=("$required")
	OPENAPI_PARAMETER_SCHEMAS+=("$schema")
}

openapi_load_parameters() {
	local file=$1
	local path=$2
	local method=$3
	local operation_id=$4
	local context="$method $path"
	local records record key name segment remainder
	local -a order=()
	local -A selected=() path_seen=() operation_seen=() declared_path=()

	records=$(OPENAPI_PATH=$path yq eval --output-format=json --indent=0 '(.paths[strenv(OPENAPI_PATH)].parameters // [])[]' "$file" </dev/null 2>/dev/null) || {
		openapi_fail "Unable to read path parameters for $context." "$OPENAPI_INVALID"
		return
	}
	while IFS= read -r record; do
		[[ -z $record ]] && continue
		openapi_parameter_identity "$record" "$context" || return $?
		key=$OPENAPI_PARAMETER_KEY
		if [[ -v "path_seen[$key]" ]]; then
			openapi_fail "Duplicate parameter '$key' in $context." "$OPENAPI_INVALID"
			return
		fi
		path_seen["$key"]=1
		selected["$key"]=$record
		order+=("$key")
	done <<<"$records"

	records=$(OPENAPI_PATH=$path OPENAPI_KEY=$method yq eval --output-format=json --indent=0 '(.paths[strenv(OPENAPI_PATH)][strenv(OPENAPI_KEY)].parameters // [])[]' "$file" </dev/null 2>/dev/null) || {
		openapi_fail "Unable to read operation parameters for $context." "$OPENAPI_INVALID"
		return
	}
	while IFS= read -r record; do
		[[ -z $record ]] && continue
		openapi_parameter_identity "$record" "$context" || return $?
		key=$OPENAPI_PARAMETER_KEY
		if [[ -v "operation_seen[$key]" ]]; then
			openapi_fail "Duplicate parameter '$key' in $context." "$OPENAPI_INVALID"
			return
		fi
		operation_seen["$key"]=1
		if [[ ! -v "selected[$key]" ]]; then
			order+=("$key")
		fi
		selected["$key"]=$record
	done <<<"$records"

	for key in "${order[@]}"; do
		openapi_add_parameter "${selected[$key]}" "$context" "$operation_id" || return $?
		if [[ $key == path:* ]]; then
			declared_path["${key#path:}"]=1
		fi
	done

	remainder=${path#/}
	while true; do
		if [[ $remainder == */* ]]; then
			segment=${remainder%%/*}
			remainder=${remainder#*/}
		else
			segment=$remainder
			remainder=''
		fi
		if [[ $segment =~ ^\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
			name=${BASH_REMATCH[1]}
			if [[ ! -v "declared_path[$name]" ]]; then
				openapi_fail "Path parameter '$name' is not declared in $context." "$OPENAPI_INVALID"
				return
			fi
		fi
		[[ -z $remainder ]] && break
	done
	for name in "${!declared_path[@]}"; do
		if [[ $path != *"{$name}"* ]]; then
			openapi_fail "Path parameter '$name' is not present in template $path." "$OPENAPI_INVALID"
			return
		fi
	done
}

openapi_load_request_body() {
	local file=$1
	local path=$2
	local method=$3
	local operation_id=$4
	local context="$method $path"
	local body body_tag keys key required required_tag content_tag media_types media_type media_key media_record media_tag schema schema_tag
	local -A seen_media_types=()

	body_tag=$(OPENAPI_PATH=$path OPENAPI_KEY=$method yq eval '.paths[strenv(OPENAPI_PATH)][strenv(OPENAPI_KEY)].requestBody | tag' "$file" </dev/null 2>/dev/null) || return "$OPENAPI_INVALID"
	[[ $body_tag != '!!null' ]] || return 0
	if [[ $body_tag != '!!map' ]]; then
		openapi_fail "Request body in $context must be a mapping." "$OPENAPI_INVALID"
		return
	fi
	body=$(OPENAPI_PATH=$path OPENAPI_KEY=$method yq eval --output-format=json --indent=0 '.paths[strenv(OPENAPI_PATH)][strenv(OPENAPI_KEY)].requestBody' "$file" </dev/null 2>/dev/null) || return "$OPENAPI_INVALID"
	keys=$(yq eval 'keys | .[]' - <<<"$body" 2>/dev/null) || return "$OPENAPI_INVALID"
	while IFS= read -r key; do
		[[ -z $key ]] && continue
		case $key in
		required | content | description) ;;
		*)
			openapi_fail "Unsupported request body field '$key' in $context." "$OPENAPI_UNSUPPORTED"
			return
			;;
		esac
	done <<<"$keys"
	required=$(yq eval '.required // false' - <<<"$body" 2>/dev/null) || return "$OPENAPI_INVALID"
	required_tag=$(yq eval '.required | tag' - <<<"$body" 2>/dev/null) || return "$OPENAPI_INVALID"
	if [[ $required_tag != '!!null' && $required_tag != '!!bool' ]]; then
		openapi_fail "Request body required flag must be boolean in $context." "$OPENAPI_INVALID"
		return
	fi
	content_tag=$(yq eval '.content | tag' - <<<"$body" 2>/dev/null) || return "$OPENAPI_INVALID"
	if [[ $content_tag != '!!map' ]]; then
		openapi_fail "Request body content must be a mapping in $context." "$OPENAPI_INVALID"
		return
	fi
	media_types=$(yq eval '.content | keys | .[]' - <<<"$body" 2>/dev/null) || return "$OPENAPI_INVALID"
	if [[ -z $media_types ]]; then
		openapi_fail "Request body content must not be empty in $context." "$OPENAPI_INVALID"
		return
	fi
	while IFS= read -r media_type; do
		[[ -z $media_type ]] && continue
		media_key=${media_type,,}
		case $media_key in
		application/json | application/yaml | application/x-yaml | text/yaml | text/x-yaml | text/plain) ;;
		*)
			openapi_fail "Unsupported request media type '$media_type' in $context." "$OPENAPI_UNSUPPORTED"
			return
			;;
		esac
		if [[ -v "seen_media_types[$media_key]" ]]; then
			openapi_fail "Duplicate request media type '$media_type' in $context." "$OPENAPI_INVALID"
			return
		fi
		seen_media_types["$media_key"]=1
		media_record=$(OPENAPI_MEDIA=$media_type yq eval --output-format=json --indent=0 '.content[strenv(OPENAPI_MEDIA)]' - <<<"$body" 2>/dev/null) || return "$OPENAPI_INVALID"
		media_tag=$(yq eval 'tag' - <<<"$media_record" 2>/dev/null) || return "$OPENAPI_INVALID"
		if [[ $media_tag != '!!map' ]]; then
			openapi_fail "Request media type '$media_type' must be a mapping in $context." "$OPENAPI_INVALID"
			return
		fi
		keys=$(yq eval 'keys | .[]' - <<<"$media_record" 2>/dev/null) || return "$OPENAPI_INVALID"
		while IFS= read -r key; do
			[[ -z $key ]] && continue
			case $key in
			schema | example | examples) ;;
			*)
				openapi_fail "Unsupported media type field '$key' for '$media_type' in $context." "$OPENAPI_UNSUPPORTED"
				return
				;;
			esac
		done <<<"$keys"
		schema_tag=$(yq eval '.schema | tag' - <<<"$media_record" 2>/dev/null) || return "$OPENAPI_INVALID"
		if [[ $schema_tag == '!!null' ]]; then
			openapi_fail "Request media type '$media_type' must define an inline schema in $context." "$OPENAPI_INVALID"
			return
		fi
		schema=$(yq eval --output-format=json --indent=0 '.schema' - <<<"$media_record" 2>/dev/null) || return "$OPENAPI_INVALID"
		openapi_validate_schema "$schema" "request media type '$media_type' in $context" 'string integer number boolean object array' || return $?
		OPENAPI_BODY_OPERATION_IDS+=("$operation_id")
		OPENAPI_BODY_REQUIRED+=("$required")
		OPENAPI_BODY_MEDIA_TYPES+=("$media_key")
		OPENAPI_BODY_SCHEMAS+=("$schema")
	done <<<"$media_types"
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
			openapi_load_parameters "$file" "$path" "$key" "$operation_id" || return $?
			openapi_load_request_body "$file" "$path" "$key" "$operation_id" || return $?
			openapi_load_middlewares "$file" "$path" "$key" "$operation_id" || return $?
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
