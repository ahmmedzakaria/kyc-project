#!/usr/bin/env bash

set -euo pipefail

CONTAINER_NAME="${KEYCLOAK_CONTAINER_NAME:-nexacore-keycloak}"
IMAGE_NAME="${KEYCLOAK_IMAGE:-quay.io/keycloak/keycloak:26.0}"

KEYCLOAK_PORT="${KEYCLOAK_PORT:-9200}"
KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-admin}"

DB_HOST="${KEYCLOAK_DB_HOST:-host.docker.internal}"
DB_PORT="${KEYCLOAK_DB_PORT:-5433}"
DB_NAME="${KEYCLOAK_DB_NAME:-keycloak}"
DB_USERNAME="${KEYCLOAK_DB_USERNAME:-postgres}"
DB_PASSWORD="${KEYCLOAK_DB_PASSWORD:-123456}"

DB_URL="jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}"

echo "Stopping existing ${CONTAINER_NAME} container if it exists..."
docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

echo "Starting Keycloak in Docker..."
docker run -d \
  --name "${CONTAINER_NAME}" \
  --add-host=host.docker.internal:host-gateway \
  -p "${KEYCLOAK_PORT}:${KEYCLOAK_PORT}" \
  -e KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN}" \
  -e KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD}" \
  -e KC_DB=postgres \
  -e KC_DB_URL="${DB_URL}" \
  -e KC_DB_USERNAME="${DB_USERNAME}" \
  -e KC_DB_PASSWORD="${DB_PASSWORD}" \
  -e KC_HTTP_ENABLED=true \
  -e KC_HOSTNAME=localhost \
  -e KC_HOSTNAME_STRICT=false \
  -e KC_HOSTNAME_STRICT_HTTPS=false \
  "${IMAGE_NAME}" \
  start-dev --http-port="${KEYCLOAK_PORT}"

cat <<EOF

Keycloak is starting.

URL:
  http://localhost:${KEYCLOAK_PORT}

Admin:
  username: ${KEYCLOAK_ADMIN}
  password: ${KEYCLOAK_ADMIN_PASSWORD}

Database:
  ${DB_URL}
  username: ${DB_USERNAME}

Run backend/frontend outside Docker with:
  AUTH_MODE=SSO
  KEYCLOAK_ISSUER_URI=http://localhost:${KEYCLOAK_PORT}/realms/kyc
  KEYCLOAK_JWK_SET_URI=http://localhost:${KEYCLOAK_PORT}/realms/kyc/protocol/openid-connect/certs
  KEYCLOAK_CLIENT_ID=nexacore-client
  KEYCLOAK_AUDIENCE=nexacore

Useful commands:
  docker logs -f ${CONTAINER_NAME}
  docker rm -f ${CONTAINER_NAME}

EOF
