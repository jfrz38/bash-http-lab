#!/usr/bin/env bash

check_bash_version() {
	if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))); then
		printf 'bash-http requires Bash 5.2 or newer (found %s).\n' "$BASH_VERSION" >&2
		return 1
	fi
}

require_command() {
	local command_name=$1

	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'bash-http requires %s for this operation.\n' "$command_name" >&2
		return 1
	fi
}

require_yq_v4() {
	local version

	require_command yq || return 1
	version=$(yq --version </dev/null 2>&1) || {
		printf 'Unable to determine the installed yq version.\n' >&2
		return 1
	}
	if [[ ! $version =~ mikefarah/yq.*version[[:space:]]+v?4\. ]]; then
		printf 'bash-http requires Mike Farah yq version 4 (found: %s).\n' "$version" >&2
		return 1
	fi
}

validate_host() {
	local host=$1
	local ipv4_pattern='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
	local dns_label_pattern='^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$'
	local -a parts=()
	local part

	if [[ $host =~ $ipv4_pattern ]]; then
		IFS='.' read -r -a parts <<<"$host"
		for part in "${parts[@]}"; do
			if ((10#$part > 255)); then
				printf 'Invalid host: %s. Use an IPv4 address or DNS hostname.\n' "$host" >&2
				return 1
			fi
		done
		return 0
	fi

	if ((${#host} == 0 || ${#host} > 253)) || [[ $host == *..* ]]; then
		printf 'Invalid host: %s. Use an IPv4 address or DNS hostname.\n' "$host" >&2
		return 1
	fi

	IFS='.' read -r -a parts <<<"$host"
	for part in "${parts[@]}"; do
		if [[ ! $part =~ $dns_label_pattern ]]; then
			printf 'Invalid host: %s. Use an IPv4 address or DNS hostname.\n' "$host" >&2
			return 1
		fi
	done

	# Dotted numeric input is an invalid IPv4 address, not a DNS hostname.
	if [[ $host =~ ^[0-9.]+$ ]]; then
		printf 'Invalid host: %s. Use an IPv4 address or DNS hostname.\n' "$host" >&2
		return 1
	fi
}

validate_port() {
	local port=$1

	if [[ ! $port =~ ^[0-9]+$ ]] || ((10#$port < 1 || 10#$port > 65535)); then
		printf 'Invalid port: %s. Expected an integer from 1 to 65535.\n' "$port" >&2
		return 1
	fi
}
