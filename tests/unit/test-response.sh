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
	for status in 400 404 405 406 413 415 500 501; do
		response_reset
		set_error_response "$status"
		response_prepare ''
		expected="HTTP/1.1 $status "
		assert_contains "$(write_response)" "$expected"
	done
}

test_prepares_structured_json_by_default() {
	response_reset
	response_set_structured 200 '{ "status": "ok" }'
	response_prepare ''
	assert_equal 'application/json' "$RESPONSE_CONTENT_TYPE"
	assert_equal '{"status":"ok"}' "$RESPONSE_BODY"
}

test_serializes_structured_yaml() {
	response_reset
	response_set_structured 200 '{"status":"ok"}'
	response_prepare 'text/yaml'
	assert_equal 'text/yaml' "$RESPONSE_CONTENT_TYPE"
	assert_equal 'status: ok' "$RESPONSE_BODY"
}

test_selects_by_quality_and_wildcards() {
	response_reset
	response_set_structured 200 '{"status":"ok"}'
	response_prepare 'application/json;q=0.2, application/*;q=0.8, text/yaml;q=0.6'
	assert_equal 'application/yaml' "$RESPONSE_CONTENT_TYPE"

	response_reset
	response_set_structured 200 '{"status":"ok"}'
	response_prepare '*/*'
	assert_equal 'application/json' "$RESPONSE_CONTENT_TYPE"
}

test_exact_q_zero_excludes_wildcard_match() {
	response_reset
	response_set_structured 200 '{"status":"ok"}'
	response_prepare 'application/json;q=0, */*;q=1'
	assert_equal 'application/yaml' "$RESPONSE_CONTENT_TYPE"
}

test_ignores_an_alternative_with_duplicate_quality_parameters() {
	response_reset
	response_set_structured 200 '{"status":"ok"}'
	response_prepare 'application/json;q=0.9;q=0.8, text/yaml;q=0.2'
	assert_equal 'text/yaml' "$RESPONSE_CONTENT_TYPE"
}

test_returns_not_acceptable_without_a_match() {
	response_reset
	response_set_structured 200 '{"status":"ok"}'
	response_prepare 'image/png, application/json;q=0, application/yaml;q=0, text/yaml;q=0'
	assert_equal '406' "$RESPONSE_STATUS"
	assert_equal 'application/json' "$RESPONSE_CONTENT_TYPE"
	assert_equal '{"error":"Not Acceptable"}' "$RESPONSE_BODY"
}

test_rejects_invalid_structured_result() {
	response_reset
	response_set_structured 200 '{invalid'
	set +e
	response_prepare ''
	local status=$?
	set -e
	assert_equal '1' "$status"
}

run_test 'serializes an exact health response' test_serializes_health_response
run_test 'adds Allow to method-not-allowed responses' test_serializes_method_not_allowed
run_test 'rejects an unknown response status' test_rejects_unknown_status
run_test 'counts response body bytes instead of characters' test_counts_response_body_bytes
run_test 'builds every central error response' test_builds_all_central_error_responses
run_test 'prepares structured JSON by default' test_prepares_structured_json_by_default
run_test 'serializes one structured result as YAML' test_serializes_structured_yaml
run_test 'selects representations by quality and wildcards' test_selects_by_quality_and_wildcards
run_test 'lets an exact q=0 exclude a wildcard match' test_exact_q_zero_excludes_wildcard_match
run_test 'ignores an alternative with duplicate quality parameters' test_ignores_an_alternative_with_duplicate_quality_parameters
run_test 'returns 406 when no representation matches' test_returns_not_acceptable_without_a_match
run_test 'rejects an invalid structured handler result' test_rejects_invalid_structured_result
finish_tests
