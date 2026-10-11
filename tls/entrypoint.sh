#!/bin/sh
set -eu

if [ "${1:-}" = /bin/sh ] && [ "${2:-}" = /opt/tls/run-nginx.sh ]; then
    envsubst '${TLS_DOMAIN}' < /opt/tls/default.conf.template > /etc/nginx/conf.d/default.conf
    exec "$@"
else
    exec /docker-entrypoint.sh "$@"
fi
