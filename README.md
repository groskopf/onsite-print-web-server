# onsite-print-web-server

An nginx-based web-server image published to GitHub Container Registry (GHCR).
It serves static files from `/usr/share/nginx/html` (currently the nginx welcome
page) and forwards requests under `/api/` to the FastAPI backend at
`backend:8000` (see `default.conf`). It routes `/attendee/` to `attendee:80` and
`/checkin/` to `checkin:80`, preserving paths and supporting Vite hot-reload
WebSockets during development. Bare app paths redirect to a trailing slash.
Service names are resolved per request, so nginx can start without those
services; requests to unavailable services return 502.

Start all services from the sibling `onsite-print-server` repo. Its
`compose.dev.yaml` enables hot reload, and `compose.deploy.yaml` runs published
images without requiring the sibling repos on the server.

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
`nginx:stable-alpine` base image, builds the local Dockerfile, and pushes
`ghcr.io/groskopf/onsite-print-web-server:1.0.0`. It stops if any step fails.
Only the tag in `.env` is published; `latest` is not updated unless it is
the version selected in that file.

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
