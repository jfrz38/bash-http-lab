#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../test-helper.sh
source "$ROOT_DIR/tests/test-helper.sh"
# shellcheck source=../../lib/dependencies.sh
source "$ROOT_DIR/lib/dependencies.sh"
# shellcheck source=../../lib/validation.sh
source "$ROOT_DIR/lib/validation.sh"

declare -a OPENAPI_PARAMETER_OPERATION_IDS=()
declare -a OPENAPI_PARAMETER_NAMES=()
declare -a OPENAPI_PARAMETER_LOCATIONS=()
declare -a OPENAPI_PARAMETER_REQUIRED=()
declare -a OPENAPI_PARAMETER_SCHEMAS=()
declare -a OPENAPI_BODY_OPERATION_IDS=()
declare -a OPENAPI_BODY_REQUIRED=()
declare -a OPENAPI_BODY_MEDIA_TYPES=()
declare -a OPENAPI_BODY_SCHEMAS=()
declare -A REQUEST_PATH_PARAMS=()
declare -A REQUEST_QUERY_PARAMS=()
declare -A REQUEST_HEADER_PARAMS=()
REQUEST_CONTENT_LENGTH=0
BODY_MEDIA_TYPE=''
BODY_FORMAT='none'
BODY_NORMALIZED_FILE=''
TEST_TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

reset_validation_context() {
	OPENAPI_PARAMETER_OPERATION_IDS=()
	OPENAPI_PARAMETER_NAMES=()
	OPENAPI_PARAMETER_LOCATIONS=()
	OPENAPI_PARAMETER_REQUIRED=()
	OPENAPI_PARAMETER_SCHEMAS=()
	OPENAPI_BODY_OPERATION_IDS=()
	OPENAPI_BODY_REQUIRED=()
	OPENAPI_BODY_MEDIA_TYPES=()
	OPENAPI_BODY_SCHEMAS=()
	REQUEST_PATH_PARAMS=()
	REQUEST_QUERY_PARAMS=()
	REQUEST_HEADER_PARAMS=()
	REQUEST_CONTENT_LENGTH=0
	BODY_MEDIA_TYPE=''
	BODY_FORMAT='none'
	BODY_NORMALIZED_FILE="$TEST_TEMP_DIR/body"
}

set_parameter_schema() {
	local location=$1
	local required=$2
	local schema=$3

	OPENAPI_PARAMETER_OPERATION_IDS=(operation)
	OPENAPI_PARAMETER_NAMES=(value)
	OPENAPI_PARAMETER_LOCATIONS=("$location")
	OPENAPI_PARAMETER_REQUIRED=("$required")
	OPENAPI_PARAMETER_SCHEMAS=("$schema")
}

test_accepts_supported_parameter_constraints() {
	reset_validation_context
	set_parameter_schema query true '{"type":"integer","enum":[2,4,6],"minimum":2,"maximum":6}'
	REQUEST_QUERY_PARAMS[value]=4
	assert_status 0 validation_validate_request operation

	set_parameter_schema header true '{"type":"boolean"}'
	REQUEST_HEADER_PARAMS[value]=true
	assert_status 0 validation_validate_request operation

	set_parameter_schema path true '{"type":"number","minimum":1.5,"maximum":2.5}'
	REQUEST_PATH_PARAMS[value]=2.25
	assert_status 0 validation_validate_request operation
}

test_rejects_missing_or_invalid_parameters() {
	reset_validation_context
	set_parameter_schema query true '{"type":"string","enum":["short","medium"],"minLength":5,"maxLength":6}'
	assert_status "$VALIDATION_BAD_REQUEST" validation_validate_request operation
	REQUEST_QUERY_PARAMS[value]=longer
	assert_status "$VALIDATION_BAD_REQUEST" validation_validate_request operation
	REQUEST_QUERY_PARAMS[value]=short
	assert_status 0 validation_validate_request operation
}

test_validates_body_type_and_media_type() {
	reset_validation_context
	OPENAPI_BODY_OPERATION_IDS=(operation)
	OPENAPI_BODY_REQUIRED=(true)
	OPENAPI_BODY_MEDIA_TYPES=(application/json)
	OPENAPI_BODY_SCHEMAS=('{"type":"object"}')
	REQUEST_CONTENT_LENGTH=2
	BODY_MEDIA_TYPE=application/json
	BODY_FORMAT=json
	printf '{}' >"$BODY_NORMALIZED_FILE"
	assert_status 0 validation_validate_request operation
	printf '[]' >"$BODY_NORMALIZED_FILE"
	assert_status "$VALIDATION_BAD_REQUEST" validation_validate_request operation
	BODY_MEDIA_TYPE=text/plain
	assert_status "$VALIDATION_UNSUPPORTED_MEDIA_TYPE" validation_validate_request operation
}

test_rejects_missing_required_body() {
	reset_validation_context
	OPENAPI_BODY_OPERATION_IDS=(operation)
	OPENAPI_BODY_REQUIRED=(true)
	OPENAPI_BODY_MEDIA_TYPES=(application/json)
	OPENAPI_BODY_SCHEMAS=('{"type":"array"}')
	assert_status "$VALIDATION_BAD_REQUEST" validation_validate_request operation
}

run_test 'accepts supported scalar parameter constraints' test_accepts_supported_parameter_constraints
run_test 'rejects missing and invalid parameter values' test_rejects_missing_or_invalid_parameters
run_test 'validates body type and declared media type' test_validates_body_type_and_media_type
run_test 'rejects a missing required body' test_rejects_missing_required_body
finish_tests
