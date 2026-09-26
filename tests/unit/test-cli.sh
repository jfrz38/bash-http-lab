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
	assert_contains "$output" 'bash-http serve OPENAPI_FILE [--host HOST] [--port PORT]'
	assert_contains "$output" 'bash-http mock OPENAPI_FILE [--host HOST] [--port PORT]'
	assert_contains "$output" 'bash-http generate OPENAPI_FILE'
}

test_missing_openapi_file() {
	local output status
	set +e
	output=$(bash "$ROOT_DIR/bin/bash-http" serve 2>&1)
	status=$?
	set -e
	assert_equal '2' "$status"
	assert_contains "$output" 'requires an OpenAPI file'
}

test_validate_openapi_file() {
	local output
	output=$(bash "$ROOT_DIR/bin/bash-http" validate "$ROOT_DIR/openapi.yaml")
	assert_equal 'OpenAPI document is valid.' "$output"
}

test_lists_openapi_routes() {
	local output
	output=$(bash "$ROOT_DIR/bin/bash-http" routes "$ROOT_DIR/openapi.yaml")
	assert_contains "$output" 'METHOD'
	assert_contains "$output" 'GET      /users/{userId}'
	assert_contains "$output" 'get_user'
}

test_invalid_port_precedes_dependency_check() {
	local output status
	set +e
	output=$(bash "$ROOT_DIR/bin/bash-http" serve "$ROOT_DIR/openapi.yaml" --port 70000 2>&1)
	status=$?
	set -e
	assert_equal '2' "$status"
	assert_contains "$output" 'Invalid port'
}

test_unsafe_host_is_rejected() {
	local output status
	set +e
	output=$(bash "$ROOT_DIR/bin/bash-http" serve "$ROOT_DIR/openapi.yaml" --host '127.0.0.1,reuseaddr' 2>&1)
	status=$?
	set -e
	assert_equal '2' "$status"
	assert_contains "$output" 'Invalid host'
}

test_invalid_ipv4_is_rejected() {
	local output status
	set +e
	output=$(bash "$ROOT_DIR/bin/bash-http" serve "$ROOT_DIR/openapi.yaml" --host '999.999.999.999' 2>&1)
	status=$?
	set -e
	assert_equal '2' "$status"
	assert_contains "$output" 'Invalid host'
}

test_invalid_dns_name_is_rejected() {
	local output status
	set +e
	output=$(bash "$ROOT_DIR/bin/bash-http" serve "$ROOT_DIR/openapi.yaml" --host 'example..test' 2>&1)
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
run_test 'requires an OpenAPI file for serve' test_missing_openapi_file
run_test 'validates an OpenAPI file' test_validate_openapi_file
run_test 'lists routes from an OpenAPI file' test_lists_openapi_routes
run_test 'rejects an invalid port before startup' test_invalid_port_precedes_dependency_check
run_test 'rejects host option injection' test_unsafe_host_is_rejected
run_test 'rejects an invalid IPv4 address' test_invalid_ipv4_is_rejected
run_test 'rejects an invalid DNS hostname' test_invalid_dns_name_is_rejected
run_test 'reports a missing socat dependency' test_missing_socat_is_actionable
finish_tests
