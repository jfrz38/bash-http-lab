#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"
# shellcheck source=../../lib/dependencies.sh
source "$ROOT_DIR/lib/dependencies.sh"
# shellcheck source=../../lib/request.sh
source "$ROOT_DIR/lib/request.sh"
# shellcheck source=../../lib/params.sh
source "$ROOT_DIR/lib/params.sh"
# shellcheck source=../../lib/body.sh
source "$ROOT_DIR/lib/body.sh"
# shellcheck source=../../lib/response.sh
source "$ROOT_DIR/lib/response.sh"
# shellcheck source=../../lib/errors.sh
source "$ROOT_DIR/lib/errors.sh"
# shellcheck source=../../lib/openapi.sh
source "$ROOT_DIR/lib/openapi.sh"
# shellcheck source=../../lib/validation.sh
source "$ROOT_DIR/lib/validation.sh"
# shellcheck source=../../middleware/request-id.sh
source "$ROOT_DIR/middleware/request-id.sh"
# shellcheck source=../../middleware/logging.sh
source "$ROOT_DIR/middleware/logging.sh"
# shellcheck source=../../lib/middleware.sh
source "$ROOT_DIR/lib/middleware.sh"
# shellcheck source=../../lib/router.sh
source "$ROOT_DIR/lib/router.sh"
# shellcheck source=../../lib/server.sh
source "$ROOT_DIR/lib/server.sh"

request_connection() {
	local output_file
	local openapi_file=${2:-$ROOT_DIR/openapi.yaml}
	local handlers_dir=${3:-$ROOT_DIR/handlers}
	output_file=$(mktemp)
	handle_connection "$openapi_file" "$handlers_dir" <<<"$1" >"$output_file" 2>"$output_file.stderr"
	CONNECTION_RESPONSE=$(<"$output_file")
	CONNECTION_STDERR=$(<"$output_file.stderr")
	rm -f "$output_file" "$output_file.stderr"
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

test_books_route() {
	local actual
	request_connection $'GET /books/1 HTTP/1.1\r\n\r'
	actual=$CONNECTION_RESPONSE
	assert_contains "$actual" 'HTTP/1.1 200 OK'
	assert_contains "$actual" 'The Left Hand of Darkness'
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

test_missing_handler() {
	local actual
	request_connection $'GET /items/special HTTP/1.1\r\nX-Request-Id: missing-handler\r\n\r' "$ROOT_DIR/tests/fixtures/routing.yaml"
	actual=$CONNECTION_RESPONSE
	assert_contains "$actual" 'HTTP/1.1 501 Not Implemented'
	assert_contains "$actual" 'X-Request-Id: missing-handler'
	assert_equal 'missing-handler' "$(jq --raw-output '.requestId' <<<"$CONNECTION_STDERR")"
	assert_equal '501' "$(jq --raw-output '.status' <<<"$CONNECTION_STDERR")"
}

test_malformed_request() {
	local actual
	request_connection $'GET /health HTTP/1.0\r\n\r'
	actual=$CONNECTION_RESPONSE
	assert_contains "$actual" 'HTTP/1.1 400 Bad Request'
}

test_request_context_reaches_handler() {
	local actual
	request_connection \
		$'POST /context/42?q=left+hand HTTP/1.1\r\nContent-Length: 14\r\nContent-Type: application/json\r\nX-Trace: abc\r\nX-Request-Id: client-42\r\n\r\n{"name":"Ada"}' \
		"$ROOT_DIR/tests/fixtures/request-context.yaml" \
		"$ROOT_DIR/tests/fixtures/handlers"
	actual=$CONNECTION_RESPONSE
	assert_contains "$actual" 'HTTP/1.1 200 OK'
	assert_contains "$actual" 'X-Request-Id: client-42'
	assert_contains "$actual" '{"path":"42","query":"left hand","header":"abc","requestId":"client-42","body":{"name":"Ada"}}'
	assert_equal 'client-42' "$(jq --raw-output '.requestId' <<<"$CONNECTION_STDERR")"
	assert_equal '200' "$(jq --raw-output '.status' <<<"$CONNECTION_STDERR")"
}

test_invalid_query_is_bad_request() {
	local actual
	request_connection \
		$'POST /context/42?q=%GG HTTP/1.1\r\nContent-Length: 0\r\n\r' \
		"$ROOT_DIR/tests/fixtures/request-context.yaml" \
		"$ROOT_DIR/tests/fixtures/handlers"
	actual=$CONNECTION_RESPONSE
	assert_contains "$actual" 'HTTP/1.1 400 Bad Request'
	assert_equal '' "$CONNECTION_STDERR"
}

test_invalid_openapi_parameter_is_bad_request() {
	local actual
	request_connection \
		$'POST /context/0?q=left+hand HTTP/1.1\r\nContent-Length: 14\r\nContent-Type: application/json\r\nX-Trace: abc\r\n\r\n{"name":"Ada"}' \
		"$ROOT_DIR/tests/fixtures/request-context.yaml" \
		"$ROOT_DIR/tests/fixtures/handlers"
	actual=$CONNECTION_RESPONSE
	assert_contains "$actual" 'HTTP/1.1 400 Bad Request'
}

test_missing_required_parameter_is_bad_request() {
	local actual
	request_connection \
		$'POST /context/42 HTTP/1.1\r\nContent-Length: 14\r\nContent-Type: application/json\r\nX-Trace: abc\r\n\r\n{"name":"Ada"}' \
		"$ROOT_DIR/tests/fixtures/request-context.yaml" \
		"$ROOT_DIR/tests/fixtures/handlers"
	actual=$CONNECTION_RESPONSE
	assert_contains "$actual" 'HTTP/1.1 400 Bad Request'
}

test_invalid_openapi_body_is_bad_request() {
	local actual
	request_connection \
		$'POST /context/42?q=left+hand HTTP/1.1\r\nContent-Length: 2\r\nContent-Type: application/json\r\nX-Trace: abc\r\n\r\n[]' \
		"$ROOT_DIR/tests/fixtures/request-context.yaml" \
		"$ROOT_DIR/tests/fixtures/handlers"
	actual=$CONNECTION_RESPONSE
	assert_contains "$actual" 'HTTP/1.1 400 Bad Request'
}

test_unsupported_media_type() {
	local actual
	request_connection \
		$'POST /context/42 HTTP/1.1\r\nContent-Length: 1\r\nContent-Type: application/octet-stream\r\n\r\nx' \
		"$ROOT_DIR/tests/fixtures/request-context.yaml" \
		"$ROOT_DIR/tests/fixtures/handlers"
	actual=$CONNECTION_RESPONSE
	assert_contains "$actual" 'HTTP/1.1 415 Unsupported Media Type'
}

test_oversized_body() {
	local actual
	request_connection $'POST /health HTTP/1.1\r\nContent-Length: 1048577\r\n\r'
	actual=$CONNECTION_RESPONSE
	assert_contains "$actual" 'HTTP/1.1 413 Content Too Large'
}

run_test 'routes GET /health' test_health_route
run_test 'ignores the query string for routing' test_health_query_route
run_test 'routes a captured book identifier' test_books_route
run_test 'returns 404 before considering the method' test_unknown_path
run_test 'returns 405 and Allow for /health' test_unsupported_health_method
run_test 'returns 501 for an operation without a handler' test_missing_handler
run_test 'returns 400 for malformed syntax' test_malformed_request
run_test 'makes the complete request context available to handlers' test_request_context_reaches_handler
run_test 'returns 400 for invalid query encoding' test_invalid_query_is_bad_request
run_test 'returns 400 for an invalid OpenAPI parameter' test_invalid_openapi_parameter_is_bad_request
run_test 'returns 400 for a missing required parameter' test_missing_required_parameter_is_bad_request
run_test 'returns 400 for an invalid OpenAPI body' test_invalid_openapi_body_is_bad_request
run_test 'returns 415 for unsupported request media' test_unsupported_media_type
run_test 'returns 413 before reading an oversized body' test_oversized_body
finish_tests
