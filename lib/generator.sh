#!/usr/bin/env bash

generate_handlers() {
	local handlers_dir=$1
	local operation_id handler_file temporary_file index
	local created=0 skipped=0

	[[ -d $handlers_dir && -w $handlers_dir ]] || {
		printf 'Handler directory is not writable: %s\n' "$handlers_dir" >&2
		return 1
	}
	for ((index = 0; index < ${#OPENAPI_ROUTE_OPERATION_IDS[@]}; index += 1)); do
		operation_id=${OPENAPI_ROUTE_OPERATION_IDS[$index]}
		handler_file="$handlers_dir/$operation_id.sh"
		if [[ -e $handler_file ]]; then
			printf 'Skipped existing handler: %s\n' "$handler_file"
			((skipped += 1))
			continue
		fi
		temporary_file=$(mktemp "$handlers_dir/.${operation_id}.XXXXXX") || return 1
		if ! printf '#!/usr/bin/env bash\n\nhandle_%s() {\n\tresponse_set_structured 501 '\''{"error":"Not Implemented"}'\''\n}\n' "$operation_id" >"$temporary_file"; then
			rm -f "$temporary_file"
			return 1
		fi
		chmod 0755 "$temporary_file" || {
			rm -f "$temporary_file"
			return 1
		}
		if ! mv "$temporary_file" "$handler_file"; then
			rm -f "$temporary_file"
			return 1
		fi
		printf 'Created handler: %s\n' "$handler_file"
		((created += 1))
	done
	printf 'Generated %s handler(s); skipped %s existing handler(s).\n' "$created" "$skipped"
}
