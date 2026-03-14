-- NOTE: Uses MODIFY COLUMN instead of ALTER COLUMN SET DEFAULT for TiDB compatibility.
ALTER TABLE current_executions MODIFY COLUMN start_version BIGINT NOT NULL DEFAULT 0;