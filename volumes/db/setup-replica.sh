#!/bin/bash
set -e

# PostgreSQL Replica Setup Script for Multi-VM
# This script initializes a PostgreSQL replica from the master database

echo "Setting up PostgreSQL replica for multi-VM deployment..."

# Wait for master database to be ready
echo "Waiting for master database at $POSTGRES_MASTER_HOST:$POSTGRES_MASTER_PORT..."
until pg_isready -h "$POSTGRES_MASTER_HOST" -p "$POSTGRES_MASTER_PORT" -U "$POSTGRES_REPLICATION_USER"; do
    echo "Master database not ready, waiting..."
    sleep 5
done

echo "Master database is ready. Setting up replica..."

# Always force fresh replica setup for proper replication
echo "Setting up fresh replica. Removing any existing data..."

# Remove any existing data
rm -rf /var/lib/postgresql/data/*

# Drop existing replication slot if it exists
echo "Checking for existing replication slot..."
PGPASSWORD="$POSTGRES_REPLICATION_PASSWORD" PGSSLMODE=disable psql \
    -h "$POSTGRES_MASTER_HOST" \
    -p "$POSTGRES_MASTER_PORT" \
    -U "$POSTGRES_REPLICATION_USER" \
    -d postgres \
    -c "SELECT pg_drop_replication_slot('replica_slot_1') WHERE EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replica_slot_1');" || true

# Create base backup from master
PGPASSWORD="$POSTGRES_REPLICATION_PASSWORD" PGSSLMODE=disable pg_basebackup \
    -h "$POSTGRES_MASTER_HOST" \
    -p "$POSTGRES_MASTER_PORT" \
    -U "$POSTGRES_REPLICATION_USER" \
    -D /var/lib/postgresql/data \
    -v \
    -P \
    -R \
    -X stream \
    -C \
    -S "replica_slot_1"
    
echo "Base backup completed successfully"
    
# Create standby.signal file (CRITICAL for replica mode)
touch /var/lib/postgresql/data/standby.signal

# Create recovery configuration
cat > /var/lib/postgresql/data/postgresql.auto.conf << EOF
# Replica configuration
primary_conninfo = 'host=$POSTGRES_MASTER_HOST port=$POSTGRES_MASTER_PORT user=$POSTGRES_REPLICATION_USER password=$POSTGRES_REPLICATION_PASSWORD application_name=replica_vm2'
primary_slot_name = 'replica_slot_1'
promote_trigger_file = '/tmp/promote_replica'
EOF

# Set proper permissions
chown -R postgres:postgres /var/lib/postgresql/data
chmod 700 /var/lib/postgresql/data

echo "Replica configuration completed"

echo "Replica setup completed successfully"
