-- PostgreSQL Replication Setup Script
-- This script sets up replication user and slots on the primary database

-- Create replication user
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replicator') THEN
        CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicator_pass';
    END IF;
END
$$;

-- Grant necessary permissions
GRANT CONNECT ON DATABASE postgres TO replicator;

-- Create replication slots for each replica
SELECT pg_create_physical_replication_slot('replica_slot_1') 
WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replica_slot_1');

SELECT pg_create_physical_replication_slot('replica_slot_2') 
WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replica_slot_2');

-- Create archive directory
\! mkdir -p /var/lib/postgresql/archive

-- Display replication status
SELECT * FROM pg_stat_replication;
