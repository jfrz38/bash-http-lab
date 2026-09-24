#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"
# shellcheck source=../../lib/openapi.sh
source "$ROOT_DIR/lib/openapi.sh"

test_loads_catalog_routes() {
	local status
	openapi_load_routes "$ROOT_DIR/openapi.yaml"
	status=$?
	assert_equal '0' "$status" "$OPENAPI_ERROR"
	((status == 0)) || return
	assert_equal '5' "${#OPENAPI_ROUTE_METHODS[@]}"
	assert_equal 'health' "${OPENAPI_ROUTE_OPERATION_IDS[0]}"
	assert_equal 'get_author' "${OPENAPI_ROUTE_OPERATION_IDS[4]}"
	assert_equal '2' "${#OPENAPI_PARAMETER_OPERATION_IDS[@]}"
	assert_equal 'bookId' "${OPENAPI_PARAMETER_NAMES[0]}"
	assert_equal '{"type":"string"}' "${OPENAPI_PARAMETER_SCHEMAS[0]}"
	assert_equal '10' "${#OPENAPI_MIDDLEWARE_NAMES[@]}"
	assert_equal 'requestId' "${OPENAPI_MIDDLEWARE_NAMES[0]}"
	assert_equal 'logging' "${OPENAPI_MIDDLEWARE_NAMES[1]}"
	assert_equal '7' "${#OPENAPI_RESPONSE_STATUSES[@]}"
	assert_equal '200' "${OPENAPI_RESPONSE_STATUSES[0]}"
	assert_equal '404' "${OPENAPI_RESPONSE_STATUSES[3]}"
	openapi_response_status_is_documented 'get_book' 404 || fail 'expected get_book 404 to be documented'
	if openapi_response_status_is_documented 'health' 404; then
		fail 'expected health 404 to be undocumented'
	fi
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

run_test 'loads routes from the catalog contract' test_loads_catalog_routes
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
