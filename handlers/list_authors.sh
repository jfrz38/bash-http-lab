#!/usr/bin/env bash

handle_list_authors() {
	response_set 200 'application/json' '[{"id":"1","name":"Ursula K. Le Guin"},{"id":"2","name":"Octavia E. Butler"}]'
}
