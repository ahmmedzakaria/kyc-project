#!/bin/bash

# Stop script on error
set -e

IMAGE_NAME="my-keycloak"
CONTAINER_NAME="nexacore-keycloak"

echo "========================================="
echo "Building Keycloak Docker Image..."
echo "========================================="

docker build -t $IMAGE_NAME .

echo "========================================="
echo "Removing existing container (if exists)..."
echo "========================================="

docker rm -f $CONTAINER_NAME 2>/dev/null || true

echo "========================================="
echo "Starting Keycloak container..."
echo "========================================="

docker run -d \
  --name $CONTAINER_NAME \
  -p 9200:9200 \
  $IMAGE_NAME

echo "========================================="
echo "Keycloak started successfully!"
echo "========================================="

echo "Access URL:"
echo "http://localhost:9200"

echo ""
echo "Admin Credentials:"
echo "username: admin"
echo "password: admin"