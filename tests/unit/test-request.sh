#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"
# shellcheck source=../../lib/request.sh
source "$ROOT_DIR/lib/request.sh"

parse_text() {
	parse_request <<<"$1"
}

test_valid_request() {
	local x_value
	parse_text $'GET /health?probe=true HTTP/1.1\r\nHost: example.test\r\nX-Value:\t a  b \t\r\n\r'
	x_value=${REQUEST_HEADERS["x-value"]}
	assert_equal 'GET' "$REQUEST_METHOD"
	assert_equal '/health' "$REQUEST_PATH"
	assert_equal 'probe=true' "$REQUEST_QUERY_STRING"
	assert_equal 'example.test' "${REQUEST_HEADERS[host]}"
	assert_equal 'a  b' "$x_value"
}

test_requires_crlf() {
	set +e
	parse_text $'GET /health HTTP/1.1\n\n'
	local status=$?
	set -e
	assert_equal "$REQUEST_PARSE_BAD_REQUEST" "$status"
}

test_rejects_duplicate_headers() {
	set +e
	parse_text $'GET /health HTTP/1.1\r\nHost: one\r\nhost: two\r\n\r'
	local status=$?
	set -e
	assert_equal "$REQUEST_PARSE_BAD_REQUEST" "$status"
}

test_rejects_folded_headers() {
	set +e
	parse_text $'GET /health HTTP/1.1\r\nHost: one\r\n continued\r\n\r'
	local status=$?
	set -e
	assert_equal "$REQUEST_PARSE_BAD_REQUEST" "$status"
}

test_rejects_lowercase_method() {
	set +e
	parse_text $'get /health HTTP/1.1\r\n\r'
	local status=$?
	set -e
	assert_equal "$REQUEST_PARSE_BAD_REQUEST" "$status"
}

test_content_length_zero_is_accepted() {
	parse_text $'GET /health HTTP/1.1\r\nContent-Length: 0\r\n\r'
}

test_positive_content_length_is_not_implemented() {
	set +e
	parse_text $'POST /health HTTP/1.1\r\nContent-Length: 1\r\n\r\nx'
	local status=$?
	set -e
	assert_equal "$REQUEST_PARSE_NOT_IMPLEMENTED" "$status"
}

test_ambiguous_framing_is_bad_request() {
	set +e
	parse_text $'POST /health HTTP/1.1\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\nx'
	local status=$?
	set -e
	assert_equal "$REQUEST_PARSE_BAD_REQUEST" "$status"
}

test_transfer_encoding_is_not_implemented() {
	set +e
	parse_text $'POST /health HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r'
	local status=$?
	set -e
	assert_equal "$REQUEST_PARSE_NOT_IMPLEMENTED" "$status"
}

test_rejects_non_decimal_content_length() {
	set +e
	parse_text $'POST /health HTTP/1.1\r\nContent-Length: +1\r\n\r'
	local status=$?
	set -e
	assert_equal "$REQUEST_PARSE_BAD_REQUEST" "$status"
}

test_rejects_malformed_header() {
	set +e
	parse_text $'GET /health HTTP/1.1\r\nMissing-Colon\r\n\r'
	local status=$?
	set -e
	assert_equal "$REQUEST_PARSE_BAD_REQUEST" "$status"
}

test_rejects_too_many_headers() {
	local request=$'GET /health HTTP/1.1\r\n'
	local index status
	for ((index = 1; index <= 101; index += 1)); do
		request+="X-$index: value"$'\r\n'
	done
	request+=$'\r'

	set +e
	parse_text "$request"
	status=$?
	set -e
	assert_equal "$REQUEST_PARSE_BAD_REQUEST" "$status"
}

test_rejects_long_request_line() {
	local target status
	printf -v target '%*s' 8193 ''
	target=${target// /a}

	set +e
	parse_text "GET /$target HTTP/1.1"$'\r\n\r'
	status=$?
	set -e
	assert_equal "$REQUEST_PARSE_BAD_REQUEST" "$status"
}

test_rejects_control_character_in_target() {
	set +e
	parse_text $'GET /health\x01 HTTP/1.1\r\n\r'
	local status=$?
	set -e
	assert_equal "$REQUEST_PARSE_BAD_REQUEST" "$status"
}

test_rejects_oversized_header_line() {
	local value status
	printf -v value '%*s' 8190 ''
	value=${value// /a}

	set +e
	parse_text "GET /health HTTP/1.1"$'\r\n'"X-Test: $value"$'\r\n\r'
	status=$?
	set -e
	assert_equal "$REQUEST_PARSE_BAD_REQUEST" "$status"
}

test_rejects_excessive_header_bytes() {
	local request=$'GET /health HTTP/1.1\r\n'
	local value index status
	printf -v value '%*s' 8000 ''
	value=${value// /a}
	for ((index = 1; index <= 9; index += 1)); do
		request+="X-$index: $value"$'\r\n'
	done
	request+=$'\r'

	set +e
	parse_text "$request"
	status=$?
	set -e
	assert_equal "$REQUEST_PARSE_BAD_REQUEST" "$status"
}

run_test 'parses request state and normalizes headers' test_valid_request
run_test 'requires CRLF line endings' test_requires_crlf
run_test 'rejects duplicate headers case-insensitively' test_rejects_duplicate_headers
run_test 'rejects obsolete folded headers' test_rejects_folded_headers
run_test 'rejects lowercase methods' test_rejects_lowercase_method
run_test 'accepts a zero content length' test_content_length_zero_is_accepted
run_test 'rejects positive content length as unsupported' test_positive_content_length_is_not_implemented
run_test 'rejects ambiguous framing' test_ambiguous_framing_is_bad_request
run_test 'rejects transfer encoding as unsupported' test_transfer_encoding_is_not_implemented
run_test 'rejects a signed content length' test_rejects_non_decimal_content_length
run_test 'rejects a malformed header' test_rejects_malformed_header
run_test 'rejects excessive header count' test_rejects_too_many_headers
run_test 'rejects an oversized request line' test_rejects_long_request_line
run_test 'rejects a control character in the request target' test_rejects_control_character_in_target
run_test 'rejects an oversized header line' test_rejects_oversized_header_line
run_test 'rejects excessive total header bytes' test_rejects_excessive_header_bytes
finish_tests
