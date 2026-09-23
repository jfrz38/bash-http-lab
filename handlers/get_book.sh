#!/usr/bin/env bash

handle_get_book() {
	case ${ROUTE_PATH_PARAMS[bookId]} in
	1) response_set 200 'application/json' '{"id":"1","title":"The Left Hand of Darkness"}' ;;
	2) response_set 200 'application/json' '{"id":"2","title":"Kindred"}' ;;
	*) set_error_response 404 ;;
	esac
}
