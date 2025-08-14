#!/bin/bash

# PostgreSQL Replica Monitoring Script
# Monitors replication lag and status

echo "Starting PostgreSQL replica monitoring..."

while true; do
    echo "=== Replica Status Check $(date) ==="
    
    # Check replica lag (connect to db-replica container using environment password)
    export PGPASSWORD="$POSTGRES_PASSWORD"
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
            echo "Status:                 Replica (in recovery)"
        else
            echo "Status:                 Master (not in recovery)"
        fi
    else
        echo "ERROR: Cannot connect to replica database"
    fi
    
    # Check replication connection info
    REPLICATION_INFO=$(psql -h db-replica -U postgres -d postgres -t -c "SELECT conninfo FROM pg_stat_wal_receiver;" 2>/dev/null | tr -d ' ')
    
    if [ -n "$REPLICATION_INFO" ] && [ "$REPLICATION_INFO" != "ERROR" ]; then
        echo "Replication source:     Connected"
        # Show master connection details
        echo "Master connection:      $REPLICATION_INFO"
    else
        echo "Replication source:     Disconnected or not available"
    fi
    
    echo "---"
    sleep 30
done
