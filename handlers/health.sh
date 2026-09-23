#!/usr/bin/env bash

handle_health() {
	response_set 200 'application/json' '{"status":"ok"}'
}
