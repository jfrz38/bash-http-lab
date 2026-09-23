#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"

TEST_HOST=${TEST_HOST:-127.0.0.1}
TEST_PORT=${TEST_PORT:-18080}
TEST_BASE_URL="http://${TEST_HOST}:${TEST_PORT}"
TEST_TMP_DIR=$(mktemp -d)
SERVER_PID=''

cleanup() {
	if [[ -n $SERVER_PID ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
		kill -- "-$SERVER_PID" 2>/dev/null || kill "$SERVER_PID" 2>/dev/null || true
		wait "$SERVER_PID" 2>/dev/null || true
	fi
	rm -rf "$TEST_TMP_DIR"
}
trap cleanup EXIT INT TERM

start_test_server() {
	set -m
	bash "$ROOT_DIR/bin/bash-http" serve --host "$TEST_HOST" --port "$TEST_PORT" \
		>"$TEST_TMP_DIR/server.stdout" 2>"$TEST_TMP_DIR/server.stderr" &
	SERVER_PID=$!
	set +m

	local attempt
	for ((attempt = 1; attempt <= 50; attempt += 1)); do
		if curl --silent --fail --max-time 1 "$TEST_BASE_URL/health" >/dev/null 2>&1; then
			return 0
		fi
		if ! kill -0 "$SERVER_PID" 2>/dev/null; then
			printf 'Server exited during startup:\n' >&2
			cat "$TEST_TMP_DIR/server.stderr" >&2
			return 1
		fi
		sleep 0.1
	done

	printf 'Server did not become ready after bounded retries.\n' >&2
	return 1
}

perform_request() {
	local method=$1
	local path=$2

	HTTP_STATUS=$(curl --silent --show-error --max-time 2 --http1.1 \
		--request "$method" \
		--dump-header "$TEST_TMP_DIR/headers" \
		--output "$TEST_TMP_DIR/body" \
		--write-out '%{http_code}' \
		"$TEST_BASE_URL$path")
	RESPONSE_HEADERS=$(<"$TEST_TMP_DIR/headers")
	RESPONSE_BODY=$(<"$TEST_TMP_DIR/body")
}

test_health_response() {
	perform_request GET '/health'
	assert_equal '200' "$HTTP_STATUS"
	assert_equal '{"status":"ok"}' "$RESPONSE_BODY"
	assert_contains "$RESPONSE_HEADERS" $'HTTP/1.1 200 OK\r'
	assert_contains "$RESPONSE_HEADERS" $'Content-Type: application/json\r'
	assert_contains "$RESPONSE_HEADERS" $'Content-Length: 15\r'
	assert_contains "$RESPONSE_HEADERS" $'Connection: close\r'
}

test_health_query_response() {
	perform_request GET '/health?probe=true'
	assert_equal '200' "$HTTP_STATUS"
	assert_equal '{"status":"ok"}' "$RESPONSE_BODY"
}

test_unknown_path_response() {
	perform_request POST '/unknown'
	assert_equal '404' "$HTTP_STATUS"
	assert_equal '{"error":"Not Found"}' "$RESPONSE_BODY"
}

test_method_not_allowed_response() {
	perform_request POST '/health'
	assert_equal '405' "$HTTP_STATUS"
	assert_equal '{"error":"Method Not Allowed"}' "$RESPONSE_BODY"
	assert_contains "$RESPONSE_HEADERS" $'Allow: GET\r'
}

test_diagnostics_do_not_reach_stdout() {
	local server_stdout
	server_stdout=$(<"$TEST_TMP_DIR/server.stdout")
	assert_equal '' "$server_stdout"
}

start_test_server
run_test 'serves the exact health response' test_health_response
run_test 'routes health requests with a query string' test_health_query_response
run_test 'returns 404 for an unknown path' test_unknown_path_response
run_test 'returns 405 and Allow for an unsupported health method' test_method_not_allowed_response
run_test 'keeps listener diagnostics out of stdout' test_diagnostics_do_not_reach_stdout
finish_tests
