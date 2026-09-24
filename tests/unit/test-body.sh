#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"
# shellcheck source=../../lib/dependencies.sh
source "$ROOT_DIR/lib/dependencies.sh"
# shellcheck source=../../lib/request.sh
source "$ROOT_DIR/lib/request.sh"
# shellcheck source=../../lib/body.sh
source "$ROOT_DIR/lib/body.sh"

cleanup() {
	body_cleanup
}
trap cleanup EXIT INT TERM

prepare_body() {
	local media_type=$1
	local content=$2
	body_context_create
	printf '%s' "$content" >"$BODY_RAW_FILE"
	REQUEST_CONTENT_LENGTH=${#content}
	REQUEST_HEADERS=(['content-type']="$media_type")
}

test_normalizes_json() {
	local normalized
	prepare_body 'Application/JSON; charset=utf-8' '{ "name": "Ada" }'
	body_normalize
	normalized=$(<"$BODY_NORMALIZED_FILE")
	assert_equal 'json' "$BODY_FORMAT"
	assert_equal 'application/json' "$BODY_MEDIA_TYPE"
	assert_equal '{"name":"Ada"}' "$normalized"
}

test_rejects_malformed_json() {
	prepare_body 'application/json' '{bad'
	assert_status "$BODY_BAD_REQUEST" body_normalize
}

test_normalizes_yaml_to_json() {
	local normalized
	prepare_body 'application/yaml' 'name: Ada'
	yq() {
		printf '{"name":"Ada"}\n'
	}
	body_normalize
	normalized=$(<"$BODY_NORMALIZED_FILE")
	assert_equal 'json' "$BODY_FORMAT"
	assert_equal '{"name":"Ada"}' "$normalized"
}

test_preserves_plain_text_bytes() {
	local normalized
	prepare_body 'text/plain; charset=utf-8' 'hello world'
	body_normalize
	normalized=$(<"$BODY_NORMALIZED_FILE")
	assert_equal 'text' "$BODY_FORMAT"
	assert_equal 'hello world' "$normalized"
}

test_requires_content_type_for_nonempty_body() {
	body_context_create
	printf 'x' >"$BODY_RAW_FILE"
	REQUEST_CONTENT_LENGTH=1
	REQUEST_HEADERS=()
	assert_status "$BODY_BAD_REQUEST" body_normalize
}

test_rejects_unsupported_media_type() {
	prepare_body 'application/octet-stream' 'x'
	assert_status "$BODY_UNSUPPORTED_MEDIA_TYPE" body_normalize
}

test_cleanup_removes_private_storage() {
	local temp_dir
	body_context_create
	temp_dir=$BODY_TEMP_DIR
	body_cleanup
	if [[ -e $temp_dir ]]; then
		printf '  Temporary body directory still exists: %s\n' "$temp_dir" >&2
		return 1
	fi
}

run_test 'validates and compacts JSON bodies' test_normalizes_json
run_test 'rejects malformed JSON bodies' test_rejects_malformed_json
run_test 'normalizes YAML bodies to JSON' test_normalizes_yaml_to_json
run_test 'preserves plain text body bytes' test_preserves_plain_text_bytes
run_test 'requires Content-Type for a nonempty body' test_requires_content_type_for_nonempty_body
run_test 'rejects unsupported media types' test_rejects_unsupported_media_type
run_test 'removes private body storage' test_cleanup_removes_private_storage
finish_tests
