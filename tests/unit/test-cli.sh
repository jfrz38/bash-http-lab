#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"
# shellcheck source=../../lib/dependencies.sh
source "$ROOT_DIR/lib/dependencies.sh"

test_help() {
	local output
	output=$(bash "$ROOT_DIR/bin/bash-http" help)
	assert_contains "$output" 'bash-http serve [--host HOST] [--port PORT]'
}

test_reserved_command() {
	local output status
	set +e
	output=$(bash "$ROOT_DIR/bin/bash-http" routes 2>&1)
	status=$?
	set -e
	assert_equal '1' "$status"
	assert_contains "$output" 'not available until Phase 2'
}

test_invalid_port_precedes_dependency_check() {
	local output status
	set +e
	output=$(bash "$ROOT_DIR/bin/bash-http" serve --port 70000 2>&1)
	status=$?
	set -e
	assert_equal '2' "$status"
	assert_contains "$output" 'Invalid port'
}

test_unsafe_host_is_rejected() {
	local output status
	set +e
	output=$(bash "$ROOT_DIR/bin/bash-http" serve --host '127.0.0.1,reuseaddr' 2>&1)
	status=$?
	set -e
	assert_equal '2' "$status"
	assert_contains "$output" 'Invalid host'
}

test_invalid_ipv4_is_rejected() {
	local output status
	set +e
	output=$(bash "$ROOT_DIR/bin/bash-http" serve --host '999.999.999.999' 2>&1)
	status=$?
	set -e
	assert_equal '2' "$status"
	assert_contains "$output" 'Invalid host'
}

test_invalid_dns_name_is_rejected() {
	local output status
	set +e
	output=$(bash "$ROOT_DIR/bin/bash-http" serve --host 'example..test' 2>&1)
	status=$?
	set -e
	assert_equal '2' "$status"
	assert_contains "$output" 'Invalid host'
}

test_missing_socat_is_actionable() {
	local output status
	set +e
	output=$(require_command command-that-does-not-exist 2>&1)
	status=$?
	set -e
	assert_equal '1' "$status"
	assert_contains "$output" 'requires command-that-does-not-exist'
}

run_test 'prints CLI help' test_help
run_test 'reports reserved Phase 2 commands' test_reserved_command
run_test 'rejects an invalid port before startup' test_invalid_port_precedes_dependency_check
run_test 'rejects host option injection' test_unsafe_host_is_rejected
run_test 'rejects an invalid IPv4 address' test_invalid_ipv4_is_rejected
run_test 'rejects an invalid DNS hostname' test_invalid_dns_name_is_rejected
run_test 'reports a missing socat dependency' test_missing_socat_is_actionable
finish_tests
