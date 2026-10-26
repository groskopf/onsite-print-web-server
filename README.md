# onsite-print-web-server

An nginx-based web-server image published to GitHub Container Registry (GHCR).
It serves static files from `/usr/share/nginx/html` (currently the nginx welcome
page) and forwards requests under `/api/` to the FastAPI backend at
`backend:8000` (see `default.conf`). It routes `/attendee/` to `attendee:80` and
`/checkin/` to `checkin:80`, and `/admin/` to `admin:80`, preserving paths and supporting Vite hot-reload
WebSockets during development. Bare app paths redirect to a trailing slash.
The independent facilitator application at `/event/` is routed to `event:80`,
with assets under `/event/assets/`. `/event` redirects to `/event/`.
It does not depend on the admin service or its assets. Deploy an updated
gateway together with the standalone event image when migrating from the
combined admin/event application.
Service names are resolved per request, so nginx can start without those
services; requests to unavailable services return 502.

API requests allow bodies up to 11 MiB in both HTTP and HTTPS configurations,
leaving multipart overhead for the backend's 10 MiB per-image upload limit.
The backend validates image contents and enforces the file size limit.
Rebuild and recreate the web-server after changing these configurations.

Start all services from the sibling `onsite-print-server` repo. Its
`compose.dev.yaml` enables hot reload, and `compose.deploy.yaml` runs published
images without requiring the sibling repos on the server.

## HTTPS and renewal

The nginx image runs HTTPS by default. `tls/default.conf.template` serves apps
and API requests on port 443; normal HTTP requests on port 80 return 403.
HTTP-01 challenges under `/.well-known/acme-challenge/` remain public, and
`/healthz` is restricted to container loopback. Keep public port 80 open for
Let's Encrypt renewal. `TLS_DOMAIN` defaults to `event.onsite-print.dk`.

Mount the full certificate volume at `/etc/letsencrypt` read-only in nginx,
and the shared challenge volume at `/var/www/certbot`. A certificate must
already exist at `live/<TLS_DOMAIN>/` before HTTPS startup.
The nginx watcher checks certificate/key contents every 60 seconds, validates
the config, and gracefully reloads changed certificates. Failures are logged
and retried while nginx retains its last loaded certificate.

This repo also builds `ghcr.io/groskopf/onsite-print-certbot` from the Dockerfile's
`certbot` target. Its renewal loop checks immediately and every 12 hours using
the webroot, logging failures and retrying. It mounts the same certificate and
challenge volumes writable. Neither container needs the Docker socket.

The top-level deployment wires these images and volumes together. Use its
`setup-https.sh <email>` for first issuance, then `start-server.sh` and
`stop-server.sh` without flags. Certificate issuance temporarily stops nginx;
renewals do not. Back up certificate private keys securely and never delete
the certificate volume when stopping the deployment.

The local `compose.yaml` explicitly runs nginx in HTTP mode on port 8080,
using `default.conf`, without certificates or Certbot. Its publishing-only
Certbot profile is not started during development.

## Publish a version

Create a GitHub personal access token (classic) with `write:packages` permission
and access to the `groskopf` namespace. Set `CR_PAT` securely in your environment
(do not commit it). If the token belongs to a different GitHub user, also set
`GHCR_USERNAME` to that user's login; it defaults to `groskopf`.

The shared `.env` file contains the image version as `IMAGE_TAG=1.0.0`.
Update this file with a new tag for each release. Keep it limited to this
single setting; do not store credentials there.

With Docker and the Docker Compose plugin installed, run from this directory:

```sh
bash docker-push.sh
```

The script logs in to GHCR using standard input, pulls the current
`nginx:stable-alpine` and `certbot/certbot:v5.0.0` base images, builds both targets,
and pushes `ghcr.io/groskopf/onsite-print-web-server:1.0.0` and
`ghcr.io/groskopf/onsite-print-certbot:1.0.0`. It stops if any step fails.
The version advances only after both images are pushed. If a push partially
succeeds, retrying may replace the same tags.
Only the current tag in `.env` is published; `latest` is not updated. Tags must
be `major.minor.patch` without leading zeros. After publishing `1.0.0`, `.env`
becomes `1.0.1` (not yet published). Failures do not increment the version.
Commit the updated `.env`; stale versions or interrupted-push retries can
still replace a registry tag. Do not run concurrent publishes.

Alternatively, trigger the **Publish release** GitHub Actions workflow from the
Actions tab (`workflow_dispatch` only, runs from `main`). It reads the pending
`IMAGE_TAG` from `.env`, builds and pushes both the `nginx` and `certbot`
images to GHCR using the built-in `GITHUB_TOKEN`, tags the published commit on
`main` with that version (no `v` prefix), and commits the incremented `.env`
back to `main`. This requires one-time setup: personal-account repos can't add
GitHub Actions to a ruleset's bypass list, so add a `RELEASE_TOKEN` repository
secret holding a fine-grained personal access token (owned by a repository
admin, scoped to this repo with Contents: Read and write permission), and add
the **Repository admin** role to the branch ruleset's bypass list for `main`.
Pushes authenticated with `RELEASE_TOKEN` are attributed to the token owner's
admin role and bypass the pull-request requirement. Renew the token before it
expires.

## Run a published version

```sh
docker compose up -d --no-build
```

The server is available at http://localhost:8080. Log in to GHCR first if the
package is private. Compose automatically reads the version from `.env`;
there is no fallback to `latest`. Leave `IMAGE_TAG` unset in your shell so it
does not override the file when running Compose directly.

## Test the publishing script

```sh
bash tests/docker-push-test.sh
```

These tests use a mocked Docker CLI and do not build or upload images.
GitHub Actions runs them on pushes and pull requests against this repo's own
publishing script; no credentials or sibling repositories are needed.

```sh
bash tests/renew-certificates-test.sh # mocked renewal scheduling/failure tests
bash tests/https-test.sh             # builds nginx image; isolated TLS/reload test
```

The TLS test uses self-signed certificates, verifies public HTTP rejection and
ACME access, then replaces the certificate and confirms nginx reloads it.
It does not request a live certificate or touch deployment volumes.
