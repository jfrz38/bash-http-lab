#!/usr/bin/env bash
# shellcheck disable=SC2034

readonly ROUTE_NOT_FOUND=40
readonly ROUTE_METHOD_NOT_ALLOWED=41
readonly ROUTE_HANDLER_MISSING=42

ROUTE_OPERATION_ID=''
ROUTE_ALLOWED_METHODS=''
declare -A ROUTE_PATH_PARAMS=()

route_split_path() {
	local path=$1
	local -n destination=$2
	local remainder segment

	destination=()
	remainder=${path#/}
	while [[ $remainder == */* ]]; do
		segment=${remainder%%/*}
		remainder=${remainder#*/}
		destination+=("$segment")
	done
	destination+=("$remainder")
}

route_template_matches() {
	local template=$1
	local request_path=$2
	local template_segment request_segment index
	local -a template_segments=() request_segments=()

	route_split_path "$template" template_segments
	route_split_path "$request_path" request_segments
	if ((${#template_segments[@]} != ${#request_segments[@]})); then
		return 1
	fi
	for ((index = 0; index < ${#template_segments[@]}; index += 1)); do
		template_segment=${template_segments[$index]}
		request_segment=${request_segments[$index]}
		if [[ $template_segment =~ ^\{[A-Za-z_][A-Za-z0-9_]*\}$ ]]; then
			[[ -n $request_segment ]] || return 1
		elif [[ $template_segment != "$request_segment" ]]; then
			return 1
		fi
	done
}

route_candidate_is_more_specific() {
	local candidate=$1
	local selected=$2
	local index candidate_parameter selected_parameter
	local -a candidate_segments=() selected_segments=()

	route_split_path "$candidate" candidate_segments
	route_split_path "$selected" selected_segments
	for ((index = 0; index < ${#candidate_segments[@]}; index += 1)); do
		candidate_parameter=0
		selected_parameter=0
		[[ ${candidate_segments[$index]} =~ ^\{.*\}$ ]] && candidate_parameter=1
		[[ ${selected_segments[$index]} =~ ^\{.*\}$ ]] && selected_parameter=1
		if ((candidate_parameter != selected_parameter)); then
			((candidate_parameter == 0))
			return
		fi
	done
	return 1
}

route_capture_parameters() {
	local template=$1
	local request_path=$2
	local index name
	local -a template_segments=() request_segments=()

	ROUTE_PATH_PARAMS=()
	route_split_path "$template" template_segments
	route_split_path "$request_path" request_segments
	for ((index = 0; index < ${#template_segments[@]}; index += 1)); do
		if [[ ${template_segments[$index]} =~ ^\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
			name=${BASH_REMATCH[1]}
			ROUTE_PATH_PARAMS["$name"]=${request_segments[$index]}
		fi
	done
}

route_resolve() {
	local request_method=$1
	local request_path=$2
	local selected_template='' candidate method index separator=''
	local -a method_order=(GET HEAD POST PUT PATCH DELETE OPTIONS TRACE)

	ROUTE_OPERATION_ID=''
	ROUTE_ALLOWED_METHODS=''
	ROUTE_PATH_PARAMS=()

	for candidate in "${OPENAPI_ROUTE_PATHS[@]}"; do
		if route_template_matches "$candidate" "$request_path"; then
			if [[ -z $selected_template ]] || route_candidate_is_more_specific "$candidate" "$selected_template"; then
				selected_template=$candidate
			fi
		fi
	done
	[[ -n $selected_template ]] || return "$ROUTE_NOT_FOUND"

	for method in "${method_order[@]}"; do
		for ((index = 0; index < ${#OPENAPI_ROUTE_METHODS[@]}; index += 1)); do
			if [[ ${OPENAPI_ROUTE_PATHS[$index]} == "$selected_template" && ${OPENAPI_ROUTE_METHODS[$index]} == "$method" ]]; then
				ROUTE_ALLOWED_METHODS+="$separator$method"
				separator=', '
				if [[ $request_method == "$method" ]]; then
					ROUTE_OPERATION_ID=${OPENAPI_ROUTE_OPERATION_IDS[$index]}
				fi
			fi
		done
	done

	[[ -n $ROUTE_OPERATION_ID ]] || return "$ROUTE_METHOD_NOT_ALLOWED"
	route_capture_parameters "$selected_template" "$request_path"
}

invoke_route_handler() {
	local handlers_dir=$1
	local operation_id=$2
	local handler_file handler_function

	if [[ ! $operation_id =~ ^[a-z][a-z0-9_]*$ ]]; then
		return "$ROUTE_HANDLER_MISSING"
	fi
	handler_file="$handlers_dir/$operation_id.sh"
	handler_function="handle_$operation_id"
	[[ -f $handler_file ]] || return "$ROUTE_HANDLER_MISSING"
	# shellcheck disable=SC1090
	source "$handler_file" || return 1
	declare -F "$handler_function" >/dev/null || return "$ROUTE_HANDLER_MISSING"
	"$handler_function"
}
