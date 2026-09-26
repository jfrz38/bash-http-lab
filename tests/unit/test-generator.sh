#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"
# shellcheck source=../../lib/openapi.sh
source "$ROOT_DIR/lib/openapi.sh"
# shellcheck source=../../lib/generator.sh
source "$ROOT_DIR/lib/generator.sh"

TEST_TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMP_DIR"' EXIT

test_generates_missing_handlers_without_overwriting() {
	local output original
	OPENAPI_ROUTE_OPERATION_IDS=(alpha beta)
	printf 'existing\n' >"$TEST_TMP_DIR/beta.sh"
	original=$(<"$TEST_TMP_DIR/beta.sh")

	output=$(generate_handlers "$TEST_TMP_DIR")

	assert_contains "$output" 'Created handler:'
	assert_contains "$output" 'Skipped existing handler:'
	assert_contains "$output" 'Generated 1 handler(s); skipped 1 existing handler(s).'
	assert_contains "$(<"$TEST_TMP_DIR/alpha.sh")" 'handle_alpha()'
	assert_contains "$(<"$TEST_TMP_DIR/alpha.sh")" 'response_set_structured 501'
	assert_equal "$original" "$(<"$TEST_TMP_DIR/beta.sh")"
}

run_test 'generates only missing handler files' test_generates_missing_handlers_without_overwriting
finish_tests
