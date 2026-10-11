#!/bin/sh
set -eu

certificate_hash() {
    sha256sum "/etc/letsencrypt/live/$TLS_DOMAIN/fullchain.pem" \
        "/etc/letsencrypt/live/$TLS_DOMAIN/privkey.pem"
}

last_hash="$(certificate_hash)"
nginx -g 'daemon off;' &
nginx_pid=$!

watch_certificates() {
    while :; do
        sleep 60
        if ! current_hash="$(certificate_hash)"; then
            echo "Cannot read renewed certificate; keeping current nginx certificate" >&2
            continue
        fi
        if [ "$current_hash" != "$last_hash" ]; then
            if nginx -t && nginx -s reload; then
                last_hash="$current_hash"
                echo "nginx reloaded renewed certificate for $TLS_DOMAIN"
            else
                echo "Certificate reload failed; retrying in 60 seconds" >&2
            fi
        fi
    done
}

watch_certificates &
watcher_pid=$!
trap 'kill "$nginx_pid" "$watcher_pid" 2>/dev/null; wait "$nginx_pid"; exit 0' TERM INT
result=0
wait "$nginx_pid" || result=$?
kill "$watcher_pid" 2>/dev/null || true
exit "$result"
