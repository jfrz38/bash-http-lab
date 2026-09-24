#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"
# shellcheck source=../../lib/openapi.sh
source "$ROOT_DIR/lib/openapi.sh"

test_loads_users_routes_and_examples() {
	local status
	openapi_load_routes "$ROOT_DIR/openapi.yaml"
	status=$?
	assert_equal '0' "$status" "$OPENAPI_ERROR" || return
	((status == 0)) || return
	assert_equal '5' "${#OPENAPI_ROUTE_METHODS[@]}" || return
	assert_equal 'health' "${OPENAPI_ROUTE_OPERATION_IDS[0]}" || return
	assert_equal 'get_user' "${OPENAPI_ROUTE_OPERATION_IDS[3]}" || return
	assert_equal '2' "${#OPENAPI_PARAMETER_OPERATION_IDS[@]}" || return
	assert_equal 'userId' "${OPENAPI_PARAMETER_NAMES[0]}" || return
	assert_equal '{"type":"integer","minimum":1}' "${OPENAPI_PARAMETER_SCHEMAS[0]}" || return
	assert_equal '10' "${#OPENAPI_MIDDLEWARE_NAMES[@]}" || return
	assert_equal 'requestId' "${OPENAPI_MIDDLEWARE_NAMES[0]}" || return
	assert_equal 'logging' "${OPENAPI_MIDDLEWARE_NAMES[1]}" || return
	assert_equal '7' "${#OPENAPI_RESPONSE_STATUSES[@]}" || return
	assert_equal '200' "${OPENAPI_RESPONSE_STATUSES[0]}" || return
	assert_equal '7' "${#OPENAPI_RESPONSE_EXAMPLE_VALUES[@]}" || return
	openapi_response_status_is_documented 'get_user' 404 || return 1
	if openapi_response_status_is_documented 'health' 404; then
		return 1
	fi
}

test_selects_mock_examples_deterministically() {
	openapi_load_routes "$ROOT_DIR/tests/fixtures/mock-responses.yaml" || return
	openapi_select_mock_response mock_direct || return 1
	assert_equal '200' "$OPENAPI_MOCK_STATUS" || return
	assert_equal '{"selected":true}' "$OPENAPI_MOCK_BODY" || return
	openapi_select_mock_response mock_named || return 1
	assert_equal '{"name":"alpha"}' "$OPENAPI_MOCK_BODY" || return
	openapi_select_mock_response mock_error || return 1
	assert_equal '404' "$OPENAPI_MOCK_STATUS" || return
	if openapi_select_mock_response mock_missing; then
		return 1
	fi
}

test_rejects_external_response_examples() {
	local status
	openapi_load_routes "$ROOT_DIR/tests/fixtures/external-response-example.yaml"
	status=$?
	assert_equal "$OPENAPI_UNSUPPORTED" "$status"
	assert_contains "$OPENAPI_ERROR" 'External response example'
}

test_rejects_unsupported_response_status() {
	local status
	openapi_load_routes "$ROOT_DIR/tests/fixtures/unsupported-response-status.yaml"
	status=$?
	assert_equal "$OPENAPI_UNSUPPORTED" "$status"
	assert_contains "$OPENAPI_ERROR" "Unsupported response status 'default'"
}

test_rejects_malformed_response() {
	local status
	openapi_load_routes "$ROOT_DIR/tests/fixtures/malformed-response.yaml"
	status=$?
	assert_equal "$OPENAPI_INVALID" "$status"
	assert_contains "$OPENAPI_ERROR" "response '200' in get /health must be a mapping"
}

test_rejects_unknown_middleware() {
	local status
	openapi_load_routes "$ROOT_DIR/tests/fixtures/unknown-middleware.yaml"
	status=$?
	assert_equal "$OPENAPI_UNSUPPORTED" "$status"
	assert_contains "$OPENAPI_ERROR" "Unknown middleware 'compression'"
}

test_rejects_duplicate_middleware() {
	local status
	openapi_load_routes "$ROOT_DIR/tests/fixtures/duplicate-middleware.yaml"
	status=$?
	assert_equal "$OPENAPI_INVALID" "$status"
	assert_contains "$OPENAPI_ERROR" "Duplicate middleware 'requestId'"
}

test_rejects_malformed_middleware_list() {
	local status
	openapi_load_routes "$ROOT_DIR/tests/fixtures/malformed-middlewares.yaml"
	status=$?
	assert_equal "$OPENAPI_INVALID" "$status"
	assert_contains "$OPENAPI_ERROR" 'x-middlewares in get /health must be a sequence'
}

test_rejects_ambiguous_paths() {
	local status
	openapi_load_routes "$ROOT_DIR/tests/fixtures/ambiguous-paths.yaml"
	status=$?
	assert_equal "$OPENAPI_INVALID" "$status"
	assert_contains "$OPENAPI_ERROR" 'Ambiguous OpenAPI path templates'
}

test_rejects_duplicate_operation_ids() {
	local status
	openapi_load_routes "$ROOT_DIR/tests/fixtures/duplicate-operation-id.yaml"
	status=$?
	assert_equal "$OPENAPI_INVALID" "$status"
	assert_contains "$OPENAPI_ERROR" 'Duplicate operationId'
}

test_rejects_unsafe_operation_id() {
	local status
	openapi_load_routes "$ROOT_DIR/tests/fixtures/unsafe-operation-id.yaml"
	status=$?
	assert_equal "$OPENAPI_INVALID" "$status"
	assert_contains "$OPENAPI_ERROR" 'Invalid operationId'
}

test_rejects_unsupported_version() {
	local status
	openapi_load_routes "$ROOT_DIR/tests/fixtures/unsupported-version.yaml"
	status=$?
	assert_equal "$OPENAPI_UNSUPPORTED" "$status"
	assert_contains "$OPENAPI_ERROR" 'Unsupported OpenAPI version'
}

test_rejects_unsupported_schema_keyword() {
	local status
	openapi_load_routes "$ROOT_DIR/tests/fixtures/unsupported-schema.yaml"
	status=$?
	assert_equal "$OPENAPI_UNSUPPORTED" "$status"
	assert_contains "$OPENAPI_ERROR" "Unsupported schema field 'pattern'"
}

test_requires_path_parameter_declarations() {
	local status
	openapi_load_routes "$ROOT_DIR/tests/fixtures/missing-path-parameter.yaml"
	status=$?
	assert_equal "$OPENAPI_INVALID" "$status"
	assert_contains "$OPENAPI_ERROR" "Path parameter 'itemId' is not declared"
}

run_test 'loads routes and response examples from the users contract' test_loads_users_routes_and_examples
run_test 'selects mock examples deterministically' test_selects_mock_examples_deterministically
run_test 'rejects external response examples' test_rejects_external_response_examples
run_test 'rejects ambiguous path templates' test_rejects_ambiguous_paths
run_test 'rejects duplicate operation IDs' test_rejects_duplicate_operation_ids
run_test 'rejects unsafe operation IDs' test_rejects_unsafe_operation_id
run_test 'rejects OpenAPI 3.1' test_rejects_unsupported_version
run_test 'rejects unsupported correctness-affecting schema keywords' test_rejects_unsupported_schema_keyword
run_test 'requires every template parameter to be declared' test_requires_path_parameter_declarations
run_test 'rejects unknown middleware' test_rejects_unknown_middleware
run_test 'rejects duplicate middleware declarations' test_rejects_duplicate_middleware
run_test 'requires middleware declarations to be a sequence' test_rejects_malformed_middleware_list
run_test 'rejects unsupported response status keys' test_rejects_unsupported_response_status
run_test 'requires response declarations to be mappings' test_rejects_malformed_response
finish_tests
