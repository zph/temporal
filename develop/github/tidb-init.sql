CREATE USER IF NOT EXISTS 'temporal'@'%' IDENTIFIED BY 'temporal';
GRANT ALL PRIVILEGES ON *.* TO 'temporal'@'%';
FLUSH PRIVILEGES;
SET GLOBAL tidb_enable_noop_functions = ON;
