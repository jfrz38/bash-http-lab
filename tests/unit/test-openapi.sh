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

run_test 'loads routes from the catalog contract' test_loads_catalog_routes
run_test 'rejects ambiguous path templates' test_rejects_ambiguous_paths
run_test 'rejects duplicate operation IDs' test_rejects_duplicate_operation_ids
run_test 'rejects unsafe operation IDs' test_rejects_unsafe_operation_id
run_test 'rejects OpenAPI 3.1' test_rejects_unsupported_version
finish_tests
