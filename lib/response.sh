#!/usr/bin/env bash

RESPONSE_STATUS=500
RESPONSE_CONTENT_TYPE='application/json'
RESPONSE_BODY=''
RESPONSE_KIND='raw'
RESPONSE_PREPARED=0
declare -a RESPONSE_EXTRA_HEADERS=()

response_reset() {
	RESPONSE_STATUS=500
	RESPONSE_CONTENT_TYPE='application/json'
	RESPONSE_BODY=''
	RESPONSE_KIND='raw'
	RESPONSE_PREPARED=0
	RESPONSE_EXTRA_HEADERS=()
}

response_set() {
	RESPONSE_STATUS=$1
	RESPONSE_CONTENT_TYPE=$2
	RESPONSE_BODY=$3
	RESPONSE_KIND='raw'
	RESPONSE_PREPARED=1
}

response_set_structured() {
	RESPONSE_STATUS=$1
	RESPONSE_CONTENT_TYPE=''
	RESPONSE_BODY=$2
	RESPONSE_KIND='structured'
	RESPONSE_PREPARED=0
}

response_add_header() {
	local name=$1
	local value=$2

	RESPONSE_EXTRA_HEADERS+=("$name: $value")
}

response_reason_phrase() {
	case $1 in
	200) REASON_PHRASE='OK' ;;
	400) REASON_PHRASE='Bad Request' ;;
	404) REASON_PHRASE='Not Found' ;;
	405) REASON_PHRASE='Method Not Allowed' ;;
	406) REASON_PHRASE='Not Acceptable' ;;
	413) REASON_PHRASE='Content Too Large' ;;
	415) REASON_PHRASE='Unsupported Media Type' ;;
	500) REASON_PHRASE='Internal Server Error' ;;
	501) REASON_PHRASE='Not Implemented' ;;
	*) return 1 ;;
	esac
}

response_trim() {
	local value=$1

	value=${value#"${value%%[!$' \t']*}"}
	value=${value%"${value##*[!$' \t']}"}
	RESPONSE_TRIMMED=$value
}

response_parse_quality() {
	local value=$1
	local decimals

	if [[ $value =~ ^0(\.([0-9]{0,3}))?$ ]]; then
		decimals=${BASH_REMATCH[2]:-}
		decimals=${decimals}000
		RESPONSE_ACCEPT_QUALITY=$((10#${decimals:0:3}))
		return 0
	fi
	if [[ $value =~ ^1(\.0{0,3})?$ ]]; then
		RESPONSE_ACCEPT_QUALITY=1000
		return 0
	fi
	return 1
}

response_accept_match() {
	local candidate=$1
	local media_range=$2

	case $media_range in
	'*/*') RESPONSE_ACCEPT_SPECIFICITY=0 ;;
	'application/*')
		[[ $candidate == application/* ]] || return 1
		RESPONSE_ACCEPT_SPECIFICITY=1
		;;
	'text/*')
		[[ $candidate == text/* ]] || return 1
		RESPONSE_ACCEPT_SPECIFICITY=1
		;;
	"$candidate") RESPONSE_ACCEPT_SPECIFICITY=2 ;;
	*) return 1 ;;
	esac
}

response_candidate_quality() {
	local candidate=$1
	local accept=$2
	local item media_range parameter name value quality specificity
	local best_quality=-1 best_specificity=-1 malformed quality_seen
	local -a items=() parts=()

	IFS=',' read -r -a items <<<"$accept"
	for item in "${items[@]}"; do
		response_trim "$item"
		item=${RESPONSE_TRIMMED,,}
		[[ -n $item ]] || continue
		IFS=';' read -r -a parts <<<"$item"
		response_trim "${parts[0]}"
		media_range=$RESPONSE_TRIMMED
		quality=1000
		malformed=0
		quality_seen=0
		for parameter in "${parts[@]:1}"; do
			response_trim "$parameter"
			parameter=$RESPONSE_TRIMMED
			if [[ $parameter != *=* ]]; then
				malformed=1
				break
			fi
			name=${parameter%%=*}
			value=${parameter#*=}
			response_trim "$name"
			name=$RESPONSE_TRIMMED
			response_trim "$value"
			value=$RESPONSE_TRIMMED
			if [[ $name != q ]] || ((quality_seen == 1)) || ! response_parse_quality "$value"; then
				malformed=1
				break
			fi
			quality=$RESPONSE_ACCEPT_QUALITY
			quality_seen=1
		done
		((malformed == 0)) || continue
		response_accept_match "$candidate" "$media_range" || continue
		specificity=$RESPONSE_ACCEPT_SPECIFICITY
		if ((specificity > best_specificity || (specificity == best_specificity && quality > best_quality))); then
			best_specificity=$specificity
			best_quality=$quality
		fi
	done

	RESPONSE_CANDIDATE_QUALITY=$best_quality
	RESPONSE_CANDIDATE_SPECIFICITY=$best_specificity
}

response_select_media_type() {
	local accept=$1
	local candidate quality specificity
	local best_media='' best_quality=-1 best_specificity=-1
	local -a candidates=('application/json' 'application/yaml' 'text/yaml')

	if [[ -z $accept ]]; then
		RESPONSE_SELECTED_MEDIA_TYPE='application/json'
		return 0
	fi
	for candidate in "${candidates[@]}"; do
		response_candidate_quality "$candidate" "$accept"
		quality=$RESPONSE_CANDIDATE_QUALITY
		specificity=$RESPONSE_CANDIDATE_SPECIFICITY
		if ((quality > 0 && (quality > best_quality || (quality == best_quality && specificity > best_specificity)))); then
			best_media=$candidate
			best_quality=$quality
			best_specificity=$specificity
		fi
	done
	[[ -n $best_media ]] || return 1
	RESPONSE_SELECTED_MEDIA_TYPE=$best_media
}

response_prepare() {
	local accept=${1:-}
	local normalized

	((RESPONSE_PREPARED == 0)) || return 0
	[[ $RESPONSE_KIND == 'structured' ]] || {
		RESPONSE_PREPARED=1
		return 0
	}
	if ! normalized=$(jq --compact-output . <<<"$RESPONSE_BODY" 2>/dev/null); then
		return 1
	fi
	if [[ $RESPONSE_STATUS == 406 ]] || ! response_select_media_type "$accept"; then
		if [[ $RESPONSE_STATUS != 406 ]]; then
			RESPONSE_STATUS=406
			normalized='{"error":"Not Acceptable"}'
		fi
		RESPONSE_CONTENT_TYPE='application/json'
		RESPONSE_BODY=$normalized
		RESPONSE_PREPARED=1
		return 0
	fi

	RESPONSE_CONTENT_TYPE=$RESPONSE_SELECTED_MEDIA_TYPE
	if [[ $RESPONSE_CONTENT_TYPE == 'application/json' ]]; then
		RESPONSE_BODY=$normalized
	else
		RESPONSE_BODY=$(yq eval --output-format=yaml --prettyPrint '.' - <<<"$normalized") || return 1
	fi
	RESPONSE_PREPARED=1
}

write_response() {
	local body_length header
	local LC_ALL=C

	if ! response_reason_phrase "$RESPONSE_STATUS"; then
		return 1
	fi
	body_length=${#RESPONSE_BODY}

	printf 'HTTP/1.1 %s %s\r\n' "$RESPONSE_STATUS" "$REASON_PHRASE"
	printf 'Content-Type: %s\r\n' "$RESPONSE_CONTENT_TYPE"
	printf 'Content-Length: %s\r\n' "$body_length"
	printf 'Connection: close\r\n'
	for header in "${RESPONSE_EXTRA_HEADERS[@]}"; do
		printf '%s\r\n' "$header"
	done
	printf '\r\n%s' "$RESPONSE_BODY"
}
