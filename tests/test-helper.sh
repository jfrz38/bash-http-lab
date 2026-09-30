#!/usr/bin/env bash

TESTS_RUN=0
TESTS_FAILED=0
TEST_ASSERTION_FAILED=0

assert_equal() {
	local expected=$1
	local actual=$2
	local message=${3:-Values should be equal}

	if [[ $expected != "$actual" ]]; then
		printf '  %s\n  expected: %q\n  actual:   %q\n' "$message" "$expected" "$actual" >&2
		TEST_ASSERTION_FAILED=1
		return 1
	fi
}

assert_contains() {
	local haystack=$1
	local needle=$2
	local message=${3:-Value should contain expected text}

	if [[ $haystack != *"$needle"* ]]; then
		printf '  %s\n  missing: %q\n  value:   %q\n' "$message" "$needle" "$haystack" >&2
		TEST_ASSERTION_FAILED=1
		return 1
	fi
}

assert_status() {
	local expected=$1
	shift
	local actual

	set +e
	"$@"
	actual=$?
	set -e
	assert_equal "$expected" "$actual" "Unexpected exit status for: $*"
}

run_test() {
	local name=$1
	local test_status
	shift

	((TESTS_RUN += 1))
	TEST_ASSERTION_FAILED=0
	if "$@"; then
		test_status=0
	else
		test_status=$?
	fi

	if ((test_status == 0 && TEST_ASSERTION_FAILED == 0)); then
		printf 'ok %s - %s\n' "$TESTS_RUN" "$name"
	else
		printf 'not ok %s - %s\n' "$TESTS_RUN" "$name"
		((TESTS_FAILED += 1))
	fi
}

finish_tests() {
	if ((TESTS_FAILED > 0)); then
		printf '%s of %s tests failed.\n' "$TESTS_FAILED" "$TESTS_RUN" >&2
		return 1
	fi
	printf '%s tests passed.\n' "$TESTS_RUN"
}
