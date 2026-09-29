#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"

TEST_HOST=${TEST_HOST:-127.0.0.1}
TEST_PORT=${TEST_PORT:-18080}
TEST_BASE_URL="http://${TEST_HOST}:${TEST_PORT}"
TEST_REQUEST_TIMEOUT_SECONDS=${TEST_REQUEST_TIMEOUT_SECONDS:-15}
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
	local server_mode=${2:-serve}
	set -m
	bash "$ROOT_DIR/bin/bash-http" "$server_mode" "$openapi_file" --host "$TEST_HOST" --port "$TEST_PORT" \
		>"$TEST_TMP_DIR/server.stdout" 2>"$TEST_TMP_DIR/server.stderr" &
	SERVER_PID=$!
	set +m

	local attempt
	for ((attempt = 1; attempt <= 100; attempt += 1)); do
		if curl --silent --max-time "$TEST_REQUEST_TIMEOUT_SECONDS" "$TEST_BASE_URL/health" >/dev/null 2>&1; then
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
	local accept=${4:-}
	local -a request_id_option=() accept_option=()

	if [[ -n $request_id ]]; then
		request_id_option=(--header "X-Request-Id: $request_id")
	fi
	if [[ -n $accept ]]; then
		accept_option=(--header "Accept: $accept")
	fi

	HTTP_STATUS=$(curl --silent --show-error --max-time "$TEST_REQUEST_TIMEOUT_SECONDS" --http1.1 \
		--request "$method" \
		"${request_id_option[@]}" \
		"${accept_option[@]}" \
		--dump-header "$TEST_TMP_DIR/headers" \
		--output "$TEST_TMP_DIR/body" \
		--write-out '%{http_code}' \
		"$TEST_BASE_URL$path")
	RESPONSE_HEADERS=$(<"$TEST_TMP_DIR/headers")
	RESPONSE_BODY=$(<"$TEST_TMP_DIR/body")
}

test_yaml_response() {
	perform_request GET '/health' '' 'text/yaml'
	assert_equal '200' "$HTTP_STATUS"
	assert_contains "$RESPONSE_HEADERS" $'Content-Type: text/yaml\r'
	assert_equal 'status: ok' "$RESPONSE_BODY"
}

test_accept_quality_prefers_yaml() {
	perform_request GET '/health' '' 'application/json;q=0.2, application/*;q=0.8'
	assert_equal '200' "$HTTP_STATUS"
	assert_contains "$RESPONSE_HEADERS" $'Content-Type: application/yaml\r'
}

test_rejects_unsupported_response_media_type() {
	perform_request GET '/health' '' 'image/png'
	assert_equal '406' "$HTTP_STATUS"
	assert_equal '{"error":"Not Acceptable"}' "$RESPONSE_BODY"
}

test_request_id_and_log_correlation() {
	local log_record
	perform_request GET '/users' 'integration-request-1'
	assert_equal '200' "$HTTP_STATUS"
	assert_contains "$RESPONSE_HEADERS" $'X-Request-Id: integration-request-1\r'
	log_record=$(jq --compact-output 'select(.requestId == "integration-request-1")' "$TEST_TMP_DIR/server.stderr")
	assert_equal 'integration-request-1' "$(jq --raw-output '.requestId' <<<"$log_record")"
	assert_equal 'GET' "$(jq --raw-output '.method' <<<"$log_record")"
	assert_equal '/users' "$(jq --raw-output '.path' <<<"$log_record")"
	assert_equal '200' "$(jq --raw-output '.status' <<<"$log_record")"
}

perform_body_request() {
	local content_type=$1
	local body=$2
	local path=${3:-/body}

	HTTP_STATUS=$(curl --silent --show-error --max-time "$TEST_REQUEST_TIMEOUT_SECONDS" --http1.1 \
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
	printf '%s' "$request" | socat -t "$TEST_REQUEST_TIMEOUT_SECONDS" - "TCP:${TEST_HOST}:${TEST_PORT}" >"$TEST_TMP_DIR/raw-response"
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

test_user_response() {
	perform_request GET '/users/1'
	assert_equal '200' "$HTTP_STATUS"
	assert_equal '{"id":1,"name":"Ada Lovelace"}' "$RESPONSE_BODY"
}

test_user_lifecycle() {
	perform_body_request 'application/json' '{"name":"Katherine Johnson","role":"engineer"}' '/users'
	assert_equal '201' "$HTTP_STATUS"
	assert_equal '3' "$(jq --raw-output '.id' <<<"$RESPONSE_BODY")"
	assert_equal 'Katherine Johnson' "$(jq --raw-output '.name' <<<"$RESPONSE_BODY")"
	assert_equal 'engineer' "$(jq --raw-output '.role' <<<"$RESPONSE_BODY")"

	perform_request GET '/users/3'
	assert_equal '200' "$HTTP_STATUS"
	assert_equal 'Katherine Johnson' "$(jq --raw-output '.name' <<<"$RESPONSE_BODY")"

	perform_request DELETE '/users/3'
	assert_equal '200' "$HTTP_STATUS"
	assert_equal 'true' "$(jq --raw-output '.deleted' <<<"$RESPONSE_BODY")"

	perform_request GET '/users/3'
	assert_equal '404' "$HTTP_STATUS"
}

test_sqlite_initialization_does_not_reseed() {
	perform_request DELETE '/users/1'
	assert_equal '200' "$HTTP_STATUS"
	stop_test_server
	start_test_server
	perform_request GET '/users/1'
	assert_equal '404' "$HTTP_STATUS"
}

test_mock_response_without_handlers() {
	perform_request GET '/users' '' 'application/yaml'
	assert_equal '200' "$HTTP_STATUS"
	assert_contains "$RESPONSE_HEADERS" $'Content-Type: application/yaml\r'
	assert_contains "$RESPONSE_BODY" 'name: Ada Lovelace'
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

export BASH_HTTP_USERS_FILE="$TEST_TMP_DIR/users.json"
cp "$ROOT_DIR/data/users.json" "$BASH_HTTP_USERS_FILE"
start_test_server
run_test 'serves the exact health response' test_health_response
run_test 'serializes a structured result as YAML' test_yaml_response
run_test 'honors Accept quality and wildcard preferences' test_accept_quality_prefers_yaml
run_test 'returns 406 for unsupported response media' test_rejects_unsupported_response_media_type
run_test 'routes health requests with a query string' test_health_query_response
run_test 'routes a captured user identifier' test_user_response
run_test 'creates, reads, and deletes a persisted user' test_user_lifecycle
run_test 'returns 404 for an unknown path' test_unknown_path_response
run_test 'returns 405 and Allow for an unsupported health method' test_method_not_allowed_response
run_test 'correlates request context, response header, and JSON log' test_request_id_and_log_correlation
run_test 'keeps listener diagnostics out of stdout' test_diagnostics_do_not_reach_stdout
stop_test_server
export BASH_HTTP_USERS_BACKEND=sqlite
export BASH_HTTP_USERS_SQLITE_FILE="$TEST_TMP_DIR/users.sqlite"
start_test_server
run_test 'creates, reads, and deletes a user through SQLite' test_user_lifecycle
run_test 'does not reseed SQLite after initialization' test_sqlite_initialization_does_not_reseed
stop_test_server
unset BASH_HTTP_USERS_BACKEND BASH_HTTP_USERS_SQLITE_FILE
start_test_server "$ROOT_DIR/tests/fixtures/body-routing.yaml"
run_test 'accepts a valid JSON body over the network' test_accepts_valid_json_body
run_test 'rejects malformed JSON over the network' test_rejects_malformed_json_body
run_test 'rejects a body with the wrong OpenAPI type' test_rejects_wrong_openapi_body_type
run_test 'returns 415 for unsupported request media' test_rejects_unsupported_media_type
run_test 'returns 413 for an oversized declared body' test_rejects_oversized_declared_body
run_test 'returns 400 for premature request-body EOF' test_rejects_premature_body_eof
stop_test_server
start_test_server "$ROOT_DIR/openapi.yaml" mock
run_test 'serves documented examples without handlers in mock mode' test_mock_response_without_handlers
finish_tests
