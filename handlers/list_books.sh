#!/usr/bin/env bash

handle_list_books() {
	response_set 200 'application/json' '[{"id":"1","title":"The Left Hand of Darkness"},{"id":"2","title":"Kindred"}]'
}
