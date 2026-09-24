#!/usr/bin/env bash

handle_get_author() {
	case ${REQUEST_PATH_PARAMS[authorId]} in
	1) response_set_structured 200 '{"id":"1","name":"Ursula K. Le Guin"}' ;;
	2) response_set_structured 200 '{"id":"2","name":"Octavia E. Butler"}' ;;
	*) set_error_response 404 ;;
	esac
}
