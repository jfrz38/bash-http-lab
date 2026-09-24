#!/usr/bin/env bash

handle_get_book() {
	case ${REQUEST_PATH_PARAMS[bookId]} in
	1) response_set_structured 200 '{"id":"1","title":"The Left Hand of Darkness"}' ;;
	2) response_set_structured 200 '{"id":"2","title":"Kindred"}' ;;
	*) set_error_response 404 ;;
	esac
}
