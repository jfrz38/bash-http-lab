#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"
# shellcheck source=../../lib/response.sh
source "$ROOT_DIR/lib/response.sh"
# shellcheck source=../../lib/errors.sh
source "$ROOT_DIR/lib/errors.sh"

test_serializes_health_response() {
	local actual expected
	response_reset
	response_set 200 'application/json' '{"status":"ok"}'
	actual=$(write_response)
	expected=$'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 15\r\nConnection: close\r\n\r\n{"status":"ok"}'
	assert_equal "$expected" "$actual"
}

test_serializes_method_not_allowed() {
	local actual
	response_reset
	set_error_response 405
	response_add_header 'Allow' 'GET'
	actual=$(write_response)
	assert_contains "$actual" $'HTTP/1.1 405 Method Not Allowed\r\n'
	assert_contains "$actual" $'Allow: GET\r\n'
	assert_contains "$actual" $'\r\n\r\n{"error":"Method Not Allowed"}'
}

test_rejects_unknown_status() {
	response_reset
	response_set 999 'text/plain' 'invalid'
	set +e
	write_response >/dev/null
	local status=$?
	set -e
	assert_equal '1' "$status"
}

test_counts_response_body_bytes() {
	local actual body
	body=$'\xc3\xa9'
	response_reset
	response_set 200 'text/plain' "$body"
	actual=$(write_response)
	assert_contains "$actual" $'Content-Length: 2\r\n'
}

test_builds_all_central_error_responses() {
	local status expected
	for status in 400 404 405 413 415 500 501; do
		response_reset
		set_error_response "$status"
		expected="HTTP/1.1 $status "
		assert_contains "$(write_response)" "$expected"
	done
}

run_test 'serializes an exact health response' test_serializes_health_response
run_test 'adds Allow to method-not-allowed responses' test_serializes_method_not_allowed
run_test 'rejects an unknown response status' test_rejects_unknown_status
run_test 'counts response body bytes instead of characters' test_counts_response_body_bytes
run_test 'builds every central error response' test_builds_all_central_error_responses
finish_tests
