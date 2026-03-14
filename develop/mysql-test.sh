#!/usr/bin/env bash
# Run MySQL persistence tests locally.
# Usage: ./develop/mysql-test.sh [go test args...]
# Example: ./develop/mysql-test.sh -run TestMySQLExecutionStore -v
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose/docker-compose.yml"

cleanup() {
  echo "Stopping MySQL..."
  docker compose -f "$COMPOSE_FILE" down mysql -v 2>/dev/null || true
}
trap cleanup EXIT

echo "Starting MySQL..."
docker compose -f "$COMPOSE_FILE" up -d mysql

echo "Waiting for MySQL..."
for i in $(seq 1 30); do
  if docker compose -f "$COMPOSE_FILE" exec -T mysql mysqladmin ping -h localhost -uroot -proot --silent 2>/dev/null; then
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "MySQL failed to start" >&2
    exit 1
  fi
  sleep 1
done

echo "MySQL ready on port 3306"

test_exit=0
go test ./common/persistence/tests/ -run TestMySQL -count 1 -timeout 10m "$@" || test_exit=$?
exit $test_exit
