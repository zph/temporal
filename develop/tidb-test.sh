#!/usr/bin/env bash
# Run MySQL persistence tests against TiDB locally.
# Usage: ./develop/tidb-test.sh [go test args...]
# Example: ./develop/tidb-test.sh -run TestMySQLExecutionStore -v
# Example: TIDB_VERSION=v8.5.5 ./develop/tidb-test.sh -v
set -euo pipefail

TIDB_PORT="${TIDB_PORT:-4000}"
TIDB_STATUS_PORT="${TIDB_STATUS_PORT:-10080}"
TIDB_VERSION="${TIDB_VERSION:-v7.5.7}"
CONTAINER_NAME="temporal-tidb-test"
INIT_CONTAINER="${CONTAINER_NAME}-init"

cleanup() {
  echo "Stopping TiDB..."
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# Start TiDB standalone (no TiKV/PD needed for tests)
# allow-expression-index is required for visibility schema's COALESCE expression indexes
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TIDB_CONFIG="${REPO_ROOT}/develop/github/tidb-config.toml"

# Remove any stale container from a previous run
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo "Starting TiDB ${TIDB_VERSION} on port ${TIDB_PORT}..."
docker run -d \
  --name "$CONTAINER_NAME" \
  -p "${TIDB_PORT}:4000" \
  -p "${TIDB_STATUS_PORT}:10080" \
  -v "${TIDB_CONFIG}:/tidb.toml:ro" \
  "pingcap/tidb:${TIDB_VERSION}" \
  -config /tidb.toml

# Wait for TiDB to be ready via its HTTP status endpoint
echo "Waiting for TiDB..."
for i in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:${TIDB_STATUS_PORT}/status" &>/dev/null; then
    # Verify expression index config is loaded
    docker logs "$CONTAINER_NAME" 2>&1 | grep -i "expression" || true
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "TiDB failed to start. Container logs:" >&2
    docker logs "$CONTAINER_NAME" 2>&1 | tail -20
    exit 1
  fi
  sleep 1
done

# Create temporal user via a throwaway mysql container (no local mysql client needed)
echo "Creating temporal user..."
docker run --rm --name "$INIT_CONTAINER" \
  --network host \
  mysql:8.0 \
  mysql -h 127.0.0.1 -P "${TIDB_PORT}" -u root -e "
    CREATE USER IF NOT EXISTS 'temporal'@'%' IDENTIFIED BY 'temporal';
    GRANT ALL PRIVILEGES ON *.* TO 'temporal'@'%';
    FLUSH PRIVILEGES;
    SET GLOBAL tidb_enable_noop_functions = ON;"

echo "TiDB ready on port ${TIDB_PORT}"

# Run tests (skip visibility schema and tests — TiDB lacks FULLTEXT and multi-valued indexes)
# Go regex doesn't support lookaheads, so we enumerate non-visibility test prefixes.
test_exit=0
MYSQL_SEEDS=127.0.0.1 MYSQL_PORT="${TIDB_PORT}" SKIP_VISIBILITY_SCHEMA=1 \
  go test ./common/persistence/tests/ \
  -run 'TestMySQL(Shard|Execution|History|TaskQueue|Task$|Fair|Matching|Metadata|Queue|ClusterMetadata|Namespace|ClosedConnection|QueueV2|NexusEndpoint)' \
  -count 1 -timeout 10m "$@" || test_exit=$?
exit $test_exit
