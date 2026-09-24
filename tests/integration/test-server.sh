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
	local openapi_file=${1:-$ROOT_DIR/openapi.yaml}
	set -m
	bash "$ROOT_DIR/bin/bash-http" serve "$openapi_file" --host "$TEST_HOST" --port "$TEST_PORT" \
		>"$TEST_TMP_DIR/server.stdout" 2>"$TEST_TMP_DIR/server.stderr" &
	SERVER_PID=$!
	set +m

	local attempt
	for ((attempt = 1; attempt <= 50; attempt += 1)); do
		if curl --silent --max-time 1 "$TEST_BASE_URL/health" >/dev/null 2>&1; then
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

stop_test_server() {
	if [[ -n $SERVER_PID ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
		kill -- "-$SERVER_PID" 2>/dev/null || kill "$SERVER_PID" 2>/dev/null || true
		wait "$SERVER_PID" 2>/dev/null || true
	fi
	SERVER_PID=''
}

perform_request() {
	local method=$1
	local path=$2
	local request_id=${3:-}
	local -a request_id_option=()

	if [[ -n $request_id ]]; then
		request_id_option=(--header "X-Request-Id: $request_id")
	fi

	HTTP_STATUS=$(curl --silent --show-error --max-time 2 --http1.1 \
		--request "$method" \
		"${request_id_option[@]}" \
		--dump-header "$TEST_TMP_DIR/headers" \
		--output "$TEST_TMP_DIR/body" \
		--write-out '%{http_code}' \
		"$TEST_BASE_URL$path")
	RESPONSE_HEADERS=$(<"$TEST_TMP_DIR/headers")
	RESPONSE_BODY=$(<"$TEST_TMP_DIR/body")
}

test_request_id_and_log_correlation() {
	local log_record
	perform_request GET '/books' 'integration-request-1'
	assert_equal '200' "$HTTP_STATUS"
	assert_contains "$RESPONSE_HEADERS" $'X-Request-Id: integration-request-1\r'
	log_record=$(jq --compact-output 'select(.requestId == "integration-request-1")' "$TEST_TMP_DIR/server.stderr")
	assert_equal 'integration-request-1' "$(jq --raw-output '.requestId' <<<"$log_record")"
	assert_equal 'GET' "$(jq --raw-output '.method' <<<"$log_record")"
	assert_equal '/books' "$(jq --raw-output '.path' <<<"$log_record")"
	assert_equal '200' "$(jq --raw-output '.status' <<<"$log_record")"
}

perform_body_request() {
	local content_type=$1
	local body=$2
	local path=${3:-/body}

	HTTP_STATUS=$(curl --silent --show-error --max-time 2 --http1.1 \
		--request POST \
		--header "Content-Type: $content_type" \
		--data-binary "$body" \
		--dump-header "$TEST_TMP_DIR/headers" \
		--output "$TEST_TMP_DIR/body" \
		--write-out '%{http_code}' \
		"$TEST_BASE_URL$path")
	RESPONSE_HEADERS=$(<"$TEST_TMP_DIR/headers")
	RESPONSE_BODY=$(<"$TEST_TMP_DIR/body")
}

perform_raw_request() {
	local request=$1
	printf '%s' "$request" | socat - "TCP:${TEST_HOST}:${TEST_PORT}" >"$TEST_TMP_DIR/raw-response"
	RAW_RESPONSE=$(<"$TEST_TMP_DIR/raw-response")
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

test_book_response() {
	perform_request GET '/books/1'
	assert_equal '200' "$HTTP_STATUS"
	assert_equal '{"id":"1","title":"The Left Hand of Darkness"}' "$RESPONSE_BODY"
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

test_accepts_valid_json_body() {
	perform_body_request 'application/json; charset=utf-8' '{"name":"Ada"}'
	assert_equal '200' "$HTTP_STATUS"
}

test_rejects_malformed_json_body() {
	perform_body_request 'application/json' '{bad'
	assert_equal '400' "$HTTP_STATUS"
	assert_equal '{"error":"Bad Request"}' "$RESPONSE_BODY"
}

test_rejects_unsupported_media_type() {
	perform_body_request 'application/octet-stream' 'data'
	assert_equal '415' "$HTTP_STATUS"
	assert_equal '{"error":"Unsupported Media Type"}' "$RESPONSE_BODY"
}

test_rejects_wrong_openapi_body_type() {
	perform_body_request 'application/json' '[]'
	assert_equal '400' "$HTTP_STATUS"
	assert_equal '{"error":"Bad Request"}' "$RESPONSE_BODY"
}

test_rejects_oversized_declared_body() {
	perform_raw_request $'POST /body HTTP/1.1\r\nHost: localhost\r\nContent-Length: 1048577\r\nContent-Type: text/plain\r\n\r\n'
	assert_contains "$RAW_RESPONSE" 'HTTP/1.1 413 Content Too Large'
}

test_rejects_premature_body_eof() {
	perform_raw_request $'POST /body HTTP/1.1\r\nHost: localhost\r\nContent-Length: 5\r\nContent-Type: text/plain\r\n\r\ntest'
	assert_contains "$RAW_RESPONSE" 'HTTP/1.1 400 Bad Request'
}

start_test_server
run_test 'serves the exact health response' test_health_response
run_test 'routes health requests with a query string' test_health_query_response
run_test 'routes a captured book identifier' test_book_response
run_test 'returns 404 for an unknown path' test_unknown_path_response
run_test 'returns 405 and Allow for an unsupported health method' test_method_not_allowed_response
run_test 'correlates request context, response header, and JSON log' test_request_id_and_log_correlation
run_test 'keeps listener diagnostics out of stdout' test_diagnostics_do_not_reach_stdout
stop_test_server
start_test_server "$ROOT_DIR/tests/fixtures/body-routing.yaml"
run_test 'accepts a valid JSON body over the network' test_accepts_valid_json_body
run_test 'rejects malformed JSON over the network' test_rejects_malformed_json_body
run_test 'rejects a body with the wrong OpenAPI type' test_rejects_wrong_openapi_body_type
run_test 'returns 415 for unsupported request media' test_rejects_unsupported_media_type
run_test 'returns 413 for an oversized declared body' test_rejects_oversized_declared_body
run_test 'returns 400 for premature request-body EOF' test_rejects_premature_body_eof
finish_tests
