#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"
# shellcheck source=../../lib/request.sh
source "$ROOT_DIR/lib/request.sh"
# shellcheck source=../../lib/router.sh
source "$ROOT_DIR/lib/router.sh"
# shellcheck source=../../lib/params.sh
source "$ROOT_DIR/lib/params.sh"

test_builds_separate_parameter_maps() {
	REQUEST_QUERY_STRING='q=left+hand&encoded=%2Fbooks%2F1'
	REQUEST_HEADERS=([host]='example.test' ['x-trace']='abc')
	ROUTE_PATH_PARAMS=([bookId]='42')

	params_build

	assert_equal '42' "${REQUEST_PATH_PARAMS[bookId]}"
	assert_equal 'left hand' "${REQUEST_QUERY_PARAMS[q]}"
	assert_equal '/books/1' "${REQUEST_QUERY_PARAMS[encoded]}"
	assert_equal 'abc' "${REQUEST_HEADER_PARAMS["x-trace"]}"
}

test_helpers_lookup_values() {
	REQUEST_QUERY_STRING='name=Octavia'
	REQUEST_HEADERS=(['content-type']='application/json')
	ROUTE_PATH_PARAMS=([authorId]='7')
	params_build

	request_path_param authorId
	assert_equal '7' "$REQUEST_PARAM_VALUE"
	request_query_param name
	assert_equal 'Octavia' "$REQUEST_PARAM_VALUE"
	request_header_param Content-Type
	assert_equal 'application/json' "$REQUEST_PARAM_VALUE"
}

test_rejects_invalid_percent_encoding() {
	REQUEST_QUERY_STRING='q=%GG'
	REQUEST_HEADERS=()
	ROUTE_PATH_PARAMS=()
	assert_status "$PARAMS_BAD_REQUEST" params_build
}

test_rejects_repeated_decoded_keys() {
	REQUEST_QUERY_STRING='name=one&%6Eame=two'
	REQUEST_HEADERS=()
	ROUTE_PATH_PARAMS=()
	assert_status "$PARAMS_BAD_REQUEST" params_build
}

test_rejects_unsafe_decoded_keys() {
	REQUEST_QUERY_STRING='name%5B0%5D=value'
	REQUEST_HEADERS=()
	ROUTE_PATH_PARAMS=()
	assert_status "$PARAMS_BAD_REQUEST" params_build
}

test_rejects_empty_query_segments() {
	REQUEST_QUERY_STRING='one=1&'
	REQUEST_HEADERS=()
	ROUTE_PATH_PARAMS=()
	assert_status "$PARAMS_BAD_REQUEST" params_build
}

test_reset_removes_previous_request_state() {
	REQUEST_QUERY_PARAMS=([old]='value')
	REQUEST_PATH_PARAMS=([old]='value')
	REQUEST_HEADER_PARAMS=([old]='value')
	REQUEST_QUERY_STRING=''
	REQUEST_HEADERS=()
	ROUTE_PATH_PARAMS=()
	params_build

	assert_equal '0' "${#REQUEST_QUERY_PARAMS[@]}"
	assert_equal '0' "${#REQUEST_PATH_PARAMS[@]}"
	assert_equal '0' "${#REQUEST_HEADER_PARAMS[@]}"
}

run_test 'builds separate path, query, and header maps' test_builds_separate_parameter_maps
run_test 'looks up parameter values through helpers' test_helpers_lookup_values
run_test 'rejects invalid query percent encoding' test_rejects_invalid_percent_encoding
run_test 'rejects repeated decoded query keys' test_rejects_repeated_decoded_keys
run_test 'rejects unsafe decoded query keys' test_rejects_unsafe_decoded_keys
run_test 'rejects empty query segments' test_rejects_empty_query_segments
run_test 'resets maps between requests' test_reset_removes_previous_request_state
finish_tests
