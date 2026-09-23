#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"
# shellcheck source=../../lib/request.sh
source "$ROOT_DIR/lib/request.sh"
# shellcheck source=../../lib/response.sh
source "$ROOT_DIR/lib/response.sh"
# shellcheck source=../../lib/errors.sh
source "$ROOT_DIR/lib/errors.sh"
# shellcheck source=../../handlers/health.sh
source "$ROOT_DIR/handlers/health.sh"
# shellcheck source=../../lib/server.sh
source "$ROOT_DIR/lib/server.sh"

request_connection() {
	local output_file
	output_file=$(mktemp)
	handle_connection <<<"$1" >"$output_file"
	CONNECTION_RESPONSE=$(<"$output_file")
	rm -f "$output_file"
}

test_health_route() {
	local actual
	request_connection $'GET /health HTTP/1.1\r\nHost: localhost\r\n\r'
	actual=$CONNECTION_RESPONSE
	assert_contains "$actual" 'HTTP/1.1 200 OK'
	assert_contains "$actual" '{"status":"ok"}'
}

test_health_query_route() {
	local actual
	request_connection $'GET /health?probe=true HTTP/1.1\r\n\r'
	actual=$CONNECTION_RESPONSE
	assert_contains "$actual" 'HTTP/1.1 200 OK'
}

test_unknown_path() {
	local actual
	request_connection $'POST /unknown HTTP/1.1\r\n\r'
	actual=$CONNECTION_RESPONSE
	assert_contains "$actual" 'HTTP/1.1 404 Not Found'
}

test_unsupported_health_method() {
	local actual
	request_connection $'POST /health HTTP/1.1\r\nContent-Length: 0\r\n\r'
	actual=$CONNECTION_RESPONSE
	assert_contains "$actual" 'HTTP/1.1 405 Method Not Allowed'
	assert_contains "$actual" $'Allow: GET\r\n'
}

test_malformed_request() {
	local actual
	request_connection $'GET /health HTTP/1.0\r\n\r'
	actual=$CONNECTION_RESPONSE
	assert_contains "$actual" 'HTTP/1.1 400 Bad Request'
}

test_unsupported_body() {
	local actual
	request_connection $'POST /health HTTP/1.1\r\nContent-Length: 1\r\n\r\nx'
	actual=$CONNECTION_RESPONSE
	assert_contains "$actual" 'HTTP/1.1 501 Not Implemented'
}

run_test 'routes GET /health' test_health_route
run_test 'ignores the query string for routing' test_health_query_route
run_test 'returns 404 before considering the method' test_unknown_path
run_test 'returns 405 and Allow for /health' test_unsupported_health_method
run_test 'returns 400 for malformed syntax' test_malformed_request
run_test 'returns 501 for unsupported request bodies' test_unsupported_body
finish_tests
