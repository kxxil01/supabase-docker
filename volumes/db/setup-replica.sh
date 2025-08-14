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

# Check if this is a fresh replica setup
if [ ! -f "/var/lib/postgresql/data/PG_VERSION" ]; then
    echo "Fresh replica setup detected. Creating base backup..."
    
    # Remove any existing data
    rm -rf /var/lib/postgresql/data/*
    
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
else
    echo "Existing replica data found. Skipping base backup."
fi

echo "Replica setup completed successfully"
