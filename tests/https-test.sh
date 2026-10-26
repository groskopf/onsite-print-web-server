#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
container=""
cleanup() {
  if [[ -n "$container" ]]; then docker rm -f "$container" >/dev/null; fi
  rm -f -- "$temp/live/localhost/fullchain.pem" "$temp/live/localhost/privkey.pem" \
    "$temp/webroot/.well-known/acme-challenge/test"
  rmdir -- "$temp/live/localhost" "$temp/live" \
    "$temp/webroot/.well-known/acme-challenge" "$temp/webroot/.well-known" "$temp/webroot" "$temp"
}
trap cleanup EXIT
mkdir -p "$temp/live/localhost" "$temp/webroot/.well-known/acme-challenge"
printf 'challenge-test' > "$temp/webroot/.well-known/acme-challenge/test"

create_certificate() {
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=localhost \
    -addext subjectAltName=DNS:localhost -set_serial "$1" \
    -keyout "$temp/live/localhost/privkey.pem" \
    -out "$temp/live/localhost/fullchain.pem" >/dev/null 2>&1
}
create_certificate 1
image="${HTTPS_TEST_IMAGE:-onsite-print-web-server-tls-test}"
docker build --target nginx -t "$image" "$root"
container="$(docker run -d --rm -e TLS_DOMAIN=localhost \
  -p 127.0.0.1::80 -p 127.0.0.1::443 \
  --mount "type=bind,src=$temp,dst=/etc/letsencrypt,readonly" \
  --mount "type=bind,src=$temp/webroot,dst=/var/www/certbot,readonly" \
  "$image")"
http_port="$(docker port "$container" 80/tcp | cut -d : -f 2)"
https_port="$(docker port "$container" 443/tcp | cut -d : -f 2)"
ready=0
for ((i=0; i<20; i++)); do
  if docker exec "$container" wget -q -O /dev/null http://127.0.0.1/healthz; then
    ready=1
    break
  fi
  sleep 1
done
[[ "$ready" == 1 ]]
[[ "$(curl --silent --fail "http://127.0.0.1:$http_port/.well-known/acme-challenge/test")" == challenge-test ]]
curl --silent --show-error --fail --cacert "$temp/live/localhost/fullchain.pem" \
  "https://localhost:$https_port/" >/dev/null
for path in / /attendee/ /checkin/ /admin/ /event /event/ /api/v2/event/ /healthz; do
  [[ "$(curl --silent --show-error -o /dev/null -w '%{http_code}' "http://127.0.0.1:$http_port$path")" == 403 ]]
done

create_certificate 2
reloaded=0
for ((i=0; i<90; i++)); do
  peer="$(openssl s_client -connect "127.0.0.1:$https_port" -servername localhost </dev/null 2>/dev/null)"
  serial="$(openssl x509 -noout -serial <<< "$peer")"
  if [[ "$serial" == serial=02 ]]; then
    reloaded=1
    break
  fi
  sleep 1
done
[[ "$reloaded" == 1 ]]
logs="$(docker logs "$container" 2>&1)"
grep -q 'nginx reloaded renewed certificate' <<< "$logs"
echo "HTTPS, HTTP challenge, HTTP rejection, and automatic certificate reload tests passed"
