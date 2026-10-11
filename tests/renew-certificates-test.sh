#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -f -- "$temp/certbot" "$temp/sleep" "$temp/output" "$temp/calls"; rmdir -- "$temp"' EXIT
cat > "$temp/certbot" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
exit "${CERTBOT_RESULT:-0}"
MOCK
cat > "$temp/sleep" <<'MOCK'
#!/bin/sh
printf 'sleep %s\n' "$*" >> "$CALLS"
kill -TERM "$PPID"
MOCK
chmod +x "$temp/certbot" "$temp/sleep"
export PATH="$temp:$PATH" CALLS="$temp/calls"
for code in 0 42; do
  export CERTBOT_RESULT="$code"
  : > "$CALLS"
  sh "$root/tls/renew-certificates.sh" > "$temp/output" 2>&1
  grep -q '^renew --non-interactive --webroot --webroot-path /var/www/certbot$' "$CALLS"
  grep -q '^sleep 43200$' "$CALLS"
  if [[ "$code" == 42 ]]; then
    grep -q 'Certificate renewal failed' "$temp/output"
  else
    [[ ! -s "$temp/output" ]]
  fi
done
echo "Renewal scheduling and failure logging tests passed"
