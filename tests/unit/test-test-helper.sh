#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"

test_records_an_early_assertion_failure() {
	local output status

	set +e
	output=$(
		(
			source "$ROOT_DIR/tests/test-helper.sh"
			# shellcheck disable=SC2317 # Callback invoked indirectly by run_test.
			fail_then_pass() {
				assert_equal 'expected' 'actual'
				assert_equal 'same' 'same'
			}
			run_test 'failed assertion followed by a passing assertion' fail_then_pass
			finish_tests
		) 2>&1
	)
	status=$?
	set -e

	assert_equal '1' "$status"
	assert_contains "$output" 'not ok 1 - failed assertion followed by a passing assertion'
	assert_contains "$output" '1 of 1 tests failed.'
}

run_test 'records an early assertion failure' test_records_an_early_assertion_failure
finish_tests
