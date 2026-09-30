#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"
# shellcheck source=../../handlers/users-repository.sh
source "$ROOT_DIR/handlers/users-repository.sh"

TEST_TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

export BASH_HTTP_USERS_BACKEND=sqlite
export BASH_HTTP_USERS_SQLITE_FILE="$TEST_TMP_DIR/users.sqlite"
users_repository_load

test_initializes_sqlite_with_example_users() {
	users_repository_initialize
	users_repository_list
	assert_equal '2' "$(jq 'length' <<<"$USERS_REPOSITORY_RESULT")"
	assert_equal 'Ada Lovelace' "$(jq --raw-output '.[0].name' <<<"$USERS_REPOSITORY_RESULT")"
}

test_preserves_json_document_during_lifecycle() {
	local body_file
	body_file="$TEST_TMP_DIR/user.json"
	printf '%s' "{\"name\":\"O'Brien\",\"profile\":{\"role\":\"engineer\"}}" >"$body_file"

	users_repository_create "$body_file"
	assert_equal '3' "$(jq --raw-output '.id' <<<"$USERS_REPOSITORY_RESULT")"
	assert_equal "O'Brien" "$(jq --raw-output '.name' <<<"$USERS_REPOSITORY_RESULT")"
	assert_equal 'engineer' "$(jq --raw-output '.profile.role' <<<"$USERS_REPOSITORY_RESULT")"

	users_repository_find_by_id 3
	assert_equal 'true' "$USERS_REPOSITORY_FOUND"
	assert_equal "O'Brien" "$(jq --raw-output '.name' <<<"$USERS_REPOSITORY_RESULT")"

	users_repository_delete 3
	assert_equal 'true' "$USERS_REPOSITORY_DELETED"
	users_repository_find_by_id 3
	assert_equal 'false' "$USERS_REPOSITORY_FOUND"
}

test_rejects_non_numeric_identifier() {
	assert_status 1 users_repository_find_by_id '1; DELETE FROM users'
	assert_status 1 users_repository_delete '1; DELETE FROM users'
	users_repository_list
	assert_equal '2' "$(jq 'length' <<<"$USERS_REPOSITORY_RESULT")"
}

test_initialization_does_not_reseed_deleted_users() {
	users_repository_delete 1
	assert_equal 'true' "$USERS_REPOSITORY_DELETED"
	users_repository_initialize
	users_repository_find_by_id 1
	assert_equal 'false' "$USERS_REPOSITORY_FOUND"
}

test_json_backend_copies_the_immutable_seed() {
	local body_file

	export BASH_HTTP_USERS_BACKEND=json
	export BASH_HTTP_USERS_FILE="$TEST_TMP_DIR/runtime/users.json"
	mkdir "$TEST_TMP_DIR/runtime"
	users_repository_load
	users_repository_initialize
	assert_equal '2' "$(jq 'length' "$BASH_HTTP_USERS_FILE")"

	body_file="$TEST_TMP_DIR/json-user.json"
	printf '%s' '{"name":"Katherine Johnson"}' >"$body_file"
	users_repository_create "$body_file"
	assert_equal '3' "$(jq 'length' "$BASH_HTTP_USERS_FILE")"
	assert_equal '2' "$(jq 'length' "$ROOT_DIR/data/users.seed.json")"
}

run_test 'initializes SQLite with the example users' test_initializes_sqlite_with_example_users
run_test 'preserves complete JSON documents in SQLite' test_preserves_json_document_during_lifecycle
run_test 'rejects non-numeric identifiers before SQL execution' test_rejects_non_numeric_identifier
run_test 'does not reseed deleted SQLite users' test_initialization_does_not_reseed_deleted_users
run_test 'copies the immutable seed for JSON runtime data' test_json_backend_copies_the_immutable_seed
finish_tests
