# TiDB Compatibility Guide

This document describes the compatibility considerations for running Temporal's MySQL persistence layer against TiDB.

## Status

The core temporal persistence schema (state store) is fully compatible with TiDB v7.5+ and v8.5+. All non-visibility persistence tests pass against TiDB with the configuration described below.

The visibility schema is **not compatible** with TiDB due to MySQL-specific features (FULLTEXT indexes, multi-valued indexes).

## Schema Changes Required

### 1. `ALTER COLUMN ... SET DEFAULT` (v1.7 migration)

TiDB does not support the `ALTER TABLE ... ALTER COLUMN ... SET DEFAULT` syntax.

**Fix:** Rewrite as `ALTER TABLE ... MODIFY COLUMN ... DEFAULT`:

```sql
-- MySQL only:
ALTER TABLE current_executions ALTER COLUMN start_version SET DEFAULT 0;

-- TiDB compatible:
ALTER TABLE current_executions MODIFY COLUMN start_version BIGINT NOT NULL DEFAULT 0;
```

### 2. `CHECK` constraints (v1.13 migration)

TiDB versions prior to 7.2 silently ignore `CHECK` constraints. Version 7.2+ enforces them. The `nexus_endpoints_partition_status` table uses `CHECK (id = 0)` to restrict to a single row. This is also enforced by the application layer via upsert on `id=0`.

**Fix:** No schema change needed. Added documentation note requiring TiDB >= 7.2 for enforcement.

### 3. `AUTO_INCREMENT` semantics (`buffered_events` table)

TiDB's `AUTO_INCREMENT` is not strictly monotonic across TiKV regions. IDs may have gaps or be non-sequential. Temporal uses the `id` column only for uniqueness within an execution, not for ordering.

**Fix:** No change needed.

## TiDB Server Configuration

TiDB requires the following configuration to support the temporal schemas:

```toml
# tidb-config.toml
[experimental]
allow-expression-index = true
```

The following SQL settings must be applied after startup:

```sql
SET GLOBAL tidb_enable_noop_functions = ON;
```

### Why these are needed

| Setting | Reason |
|---------|--------|
| `allow-expression-index` | The visibility schema uses expression indexes with `COALESCE(...)`. Without this, TiDB rejects `CREATE INDEX` on expressions containing "unsafe" functions. |
| `tidb_enable_noop_functions` | Temporal's shard locking uses `LOCK IN SHARE MODE`, which is a no-op in TiDB. Without this setting, TiDB returns an error instead of silently accepting it. |

## Visibility Schema Incompatibilities

The visibility schema (`schema/mysql/v8/visibility/`) has several features that TiDB does not support. These are **not addressed** by this compatibility work and would require a TiDB-specific visibility schema.

| Feature | Where Used | TiDB Status |
|---------|-----------|-------------|
| `FULLTEXT` indexes | `custom_search_attributes` (Text01-03) | Not supported |
| `CAST(... AS CHAR(255) ARRAY)` multi-valued indexes | Multiple visibility migrations (v1.2, v1.3, v1.7, v1.10, v1.11, v1.13) | Not supported |
| `GENERATED ALWAYS AS` with `CONVERT_TZ` + `REGEXP_REPLACE` | Datetime search attributes in `custom_search_attributes` and `chasm_search_attributes` | May not work — complex expressions in generated columns have limited support |

## Testing

### Local testing

```bash
# Run core persistence tests against TiDB (default v7.5.7)
./develop/tidb-test.sh -v

# Test against a specific version
TIDB_VERSION=v8.5.5 ./develop/tidb-test.sh -v

# Run against MySQL for comparison
./develop/mysql-test.sh -v
```

The TiDB test script automatically:
- Starts a standalone TiDB container (no TiKV/PD needed)
- Applies the required config (`allow-expression-index`)
- Creates the `temporal` user and enables `noop_functions`
- Runs non-visibility persistence tests
- Cleans up on exit

### CI

TiDB v7.5.7 and v8.5.5 are included in the GitHub Actions test matrix using the `mysql8` persistence driver with overridden `MYSQL_SEEDS` and `MYSQL_PORT` environment variables. TiDB speaks the MySQL wire protocol, so no separate driver is needed.

## Test Results

All core persistence tests (484 tests) pass on both TiDB v7.5.7 and v8.5.5. The 37 visibility tests are skipped due to schema incompatibilities described above.

## Minimum TiDB Version

**TiDB 7.2+** is recommended:
- `CHECK` constraints are enforced (7.2+)
- Expression indexes are supported with config flag (7.1+)
- `tidb_enable_noop_functions` is available (4.0+)
