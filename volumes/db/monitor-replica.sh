#!/bin/bash

# PostgreSQL Replica Monitoring Script
# Monitors replication lag and status

echo "Starting PostgreSQL replica monitoring..."

while true; do
    echo "=== Replica Status Check $(date) ==="
    
    # Set password for PostgreSQL connections
    export PGPASSWORD="$POSTGRES_PASSWORD"
    
    # Check replica status (connect to local db-replica container)
    echo "--- REPLICA STATUS ---"
    LAG=$(psql -h db-replica -U postgres -d postgres -t -c "SELECT CASE WHEN pg_is_in_recovery() THEN COALESCE(EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())), 0) ELSE 0 END AS lag_seconds;" 2>/dev/null | tr -d ' ')
    
    if [ -n "$LAG" ] && [ "$LAG" != "ERROR" ]; then
        echo "Replica lag:            ${LAG} seconds"
        
        # Check if lag is concerning (> 60 seconds) using shell arithmetic
        if [ "${LAG%.*}" -gt 60 ] 2>/dev/null; then
            echo "WARNING: High replication lag detected!"
        fi
        
        # Check if replica is in recovery mode
        RECOVERY=$(psql -h db-replica -U postgres -d postgres -t -c "SELECT pg_is_in_recovery();" 2>/dev/null | tr -d ' ')
        if [ "$RECOVERY" = "t" ]; then
            echo "Replica status:         In recovery (replica)"
        else
            echo "Replica status:         Not in recovery (master)"
        fi
        
        # Check replication connection info from replica side
        REPLICATION_INFO=$(psql -h db-replica -U postgres -d postgres -t -c "SELECT conninfo FROM pg_stat_wal_receiver;" 2>/dev/null | tr -d ' ')
        if [ -n "$REPLICATION_INFO" ] && [ "$REPLICATION_INFO" != "ERROR" ]; then
            echo "Replication receiver:   Connected"
        else
            echo "Replication receiver:   Disconnected"
        fi
    else
        echo "ERROR: Cannot connect to replica database"
    fi
    
    # Check master status (direct connection to PostgreSQL master)
    echo "--- MASTER STATUS ---"
    if [ -n "$POSTGRES_MASTER_HOST" ]; then
        # Connect directly to PostgreSQL master on port 5433 (replication port)
        export PGPASSWORD="${POSTGRES_REPLICATION_PASSWORD:-replicator_pass}"
        MASTER_STATUS=$(PGSSLMODE=disable psql -h "$POSTGRES_MASTER_HOST" -p 5433 -U "${POSTGRES_REPLICATION_USER:-replicator}" -d postgres -t -c "SELECT COUNT(*) FROM pg_stat_replication;" 2>/dev/null | tr -d ' ')
        
        if [ -n "$MASTER_STATUS" ] && [ "$MASTER_STATUS" != "ERROR" ]; then
            echo "Master connection:      Connected ($POSTGRES_MASTER_HOST:5433)"
            echo "Connection method:      Direct PostgreSQL master"
            echo "Active replicas:        $MASTER_STATUS"
            
            # Get detailed replication info from master
            REPLICATION_DETAILS=$(PGSSLMODE=disable psql -h "$POSTGRES_MASTER_HOST" -p 5433 -U "${POSTGRES_REPLICATION_USER:-replicator}" -d postgres -t -c "SELECT application_name, client_addr, state, sync_state FROM pg_stat_replication;" 2>/dev/null)
            if [ -n "$REPLICATION_DETAILS" ]; then
                echo "Replication details:    $REPLICATION_DETAILS"
            fi
        else
            echo "Master connection:      Failed ($POSTGRES_MASTER_HOST:5433)"
            echo "Connection method:      Direct PostgreSQL master"
            echo "Note:                   Check master database and replication user"
            echo "Active replicas:        Unknown"
        fi
    else
        echo "Master connection:      No POSTGRES_MASTER_HOST configured"
    fi
    
    echo "---"
    sleep 30
done
