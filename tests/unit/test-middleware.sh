#!/usr/bin/env bash
# shellcheck disable=SC2317,SC2329

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"
# shellcheck source=../../lib/response.sh
source "$ROOT_DIR/lib/response.sh"
# shellcheck source=../../middleware/request-id.sh
source "$ROOT_DIR/middleware/request-id.sh"
# shellcheck source=../../middleware/logging.sh
source "$ROOT_DIR/middleware/logging.sh"
# shellcheck source=../../lib/middleware.sh
source "$ROOT_DIR/lib/middleware.sh"

declare -a OPENAPI_MIDDLEWARE_OPERATION_IDS=()
declare -a OPENAPI_MIDDLEWARE_NAMES=()
declare -A REQUEST_HEADERS=()
REQUEST_METHOD=''
REQUEST_PATH=''

test_runs_hooks_in_declared_order() {
	MIDDLEWARE_EVENTS=''
	OPENAPI_MIDDLEWARE_OPERATION_IDS=(test test)
	OPENAPI_MIDDLEWARE_NAMES=(first second)
	middleware_first_before() { MIDDLEWARE_EVENTS+='first:before '; }
	middleware_second_before() { MIDDLEWARE_EVENTS+='second:before '; }
	middleware_first_after() { MIDDLEWARE_EVENTS+='first:after '; }
	middleware_second_after() { MIDDLEWARE_EVENTS+='second:after'; }

	middleware_reset
	middleware_run_before test
	middleware_run_after test
	assert_equal 'first:before second:before first:after second:after' "$MIDDLEWARE_EVENTS"
}

test_preserves_valid_request_id() {
	REQUEST_HEADERS=(["x-request-id"]='client.request-42')
	RESPONSE_EXTRA_HEADERS=('X-Request-Id: stale' 'X-Test: retained')
	middleware_request_id_before
	middleware_request_id_after
	assert_equal 'client.request-42' "$REQUEST_ID"
	assert_equal '2' "${#RESPONSE_EXTRA_HEADERS[@]}"
	assert_equal 'X-Test: retained' "${RESPONSE_EXTRA_HEADERS[0]}"
	assert_equal 'X-Request-Id: client.request-42' "${RESPONSE_EXTRA_HEADERS[1]}"
}

test_generates_id_for_invalid_client_value() {
	REQUEST_HEADERS=(["x-request-id"]='invalid value')
	RESPONSE_EXTRA_HEADERS=()
	middleware_request_id_before
	[[ $REQUEST_ID =~ ^[0-9a-f-]{36}$ ]]
}

test_emits_json_request_log() {
	local output
	REQUEST_ID='request-1'
	REQUEST_METHOD='GET'
	REQUEST_PATH='/health'
	RESPONSE_STATUS=200
	middleware_logging_before
	output=$(middleware_logging_after 2>&1)
	assert_equal 'request-1' "$(jq --raw-output '.requestId' <<<"$output")"
	assert_equal 'GET' "$(jq --raw-output '.method' <<<"$output")"
	assert_equal '/health' "$(jq --raw-output '.path' <<<"$output")"
	assert_equal '200' "$(jq --raw-output '.status' <<<"$output")"
	[[ $(jq --raw-output '.durationMs' <<<"$output") =~ ^[0-9]+$ ]]
}

run_test 'runs middleware hooks in declaration order' test_runs_hooks_in_declared_order
run_test 'preserves one valid client request ID' test_preserves_valid_request_id
run_test 'generates an ID for an invalid client value' test_generates_id_for_invalid_client_value
run_test 'emits a structured JSON request log' test_emits_json_request_log
finish_tests
