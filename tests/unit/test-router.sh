#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"
# shellcheck source=../../lib/openapi.sh
source "$ROOT_DIR/lib/openapi.sh"
# shellcheck source=../../lib/router.sh
source "$ROOT_DIR/lib/router.sh"

set_routes() {
	OPENAPI_ROUTE_METHODS=(GET POST GET GET)
	OPENAPI_ROUTE_PATHS=(
		'/items/{itemId}'
		'/items/{itemId}'
		'/items/special'
		'/parents/{parentId}/items/{itemId}'
	)
	OPENAPI_ROUTE_OPERATION_IDS=(get_item create_item get_special_item get_parent_item)
}

test_static_route_precedes_parameter() {
	set_routes
	route_resolve GET '/items/special'
	assert_equal 'get_special_item' "$ROUTE_OPERATION_ID"
}

test_static_precedence_is_independent_of_document_order() {
	OPENAPI_ROUTE_METHODS=(GET GET)
	OPENAPI_ROUTE_PATHS=('/a/{first}/c' '/a/b/{second}')
	OPENAPI_ROUTE_OPERATION_IDS=(first_operation second_operation)
	route_resolve GET '/a/b/c'
	assert_equal 'second_operation' "$ROUTE_OPERATION_ID"

	OPENAPI_ROUTE_PATHS=('/a/b/{second}' '/a/{first}/c')
	OPENAPI_ROUTE_OPERATION_IDS=(second_operation first_operation)
	route_resolve GET '/a/b/c'
	assert_equal 'second_operation' "$ROUTE_OPERATION_ID"
}

test_captures_path_parameter() {
	set_routes
	route_resolve GET '/items/42'
	assert_equal 'get_item' "$ROUTE_OPERATION_ID"
	assert_equal '42' "${ROUTE_PATH_PARAMS[itemId]}"
}

test_captures_multiple_parameters() {
	set_routes
	route_resolve GET '/parents/7/items/42'
	assert_equal '7' "${ROUTE_PATH_PARAMS[parentId]}"
	assert_equal '42' "${ROUTE_PATH_PARAMS[itemId]}"
}

test_returns_method_not_allowed() {
	local status
	set_routes
	route_resolve DELETE '/items/42'
	status=$?
	assert_equal "$ROUTE_METHOD_NOT_ALLOWED" "$status"
	assert_equal 'GET, POST' "$ROUTE_ALLOWED_METHODS"
}

test_returns_not_found_for_unknown_or_trailing_path() {
	local unknown_status trailing_status
	set_routes
	route_resolve GET '/unknown'
	unknown_status=$?
	route_resolve GET '/items/42/'
	trailing_status=$?
	assert_equal "$ROUTE_NOT_FOUND" "$unknown_status"
	assert_equal "$ROUTE_NOT_FOUND" "$trailing_status"
}

test_rejects_unsafe_handler_identifier() {
	local status
	invoke_route_handler "$ROOT_DIR/handlers" '../../commands'
	status=$?
	assert_equal "$ROUTE_HANDLER_MISSING" "$status"
}

run_test 'prefers a static route over a parameter route' test_static_route_precedes_parameter
run_test 'applies static precedence independently of document order' test_static_precedence_is_independent_of_document_order
run_test 'captures one path parameter' test_captures_path_parameter
run_test 'captures multiple path parameters' test_captures_multiple_parameters
run_test 'reports allowed methods for a known path' test_returns_method_not_allowed
run_test 'distinguishes unknown and trailing paths' test_returns_not_found_for_unknown_or_trailing_path
run_test 'does not resolve unsafe handler identifiers' test_rejects_unsafe_handler_identifier
finish_tests
