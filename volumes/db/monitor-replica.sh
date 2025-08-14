#!/bin/bash

# PostgreSQL Replica Monitoring Script
# Monitors replication lag and status

echo "Starting PostgreSQL replica monitoring..."

while true; do
    echo "=== Replica Status Check $(date) ==="
    
    # Check replica lag
    LAG=$(psql -h $POSTGRES_REPLICA_HOST -U postgres -d postgres -t -c "SELECT CASE WHEN pg_is_in_recovery() THEN EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) ELSE 0 END AS lag_seconds;" 2>/dev/null || echo "ERROR")
    
    if [ "$LAG" != "ERROR" ]; then
        echo "Replica lag: ${LAG} seconds"
        
        # Check if lag is concerning (> 60 seconds)
        if (( $(echo "$LAG > 60" | bc -l) )); then
            echo "WARNING: High replication lag detected!"
        fi
    else
        echo "ERROR: Cannot connect to replica database"
    fi
    
    # Check replication status on master
    REPLICATION_STATUS=$(psql -h $POSTGRES_MASTER_HOST -U postgres -d postgres -t -c "SELECT application_name, state, sync_state FROM pg_stat_replication;" 2>/dev/null || echo "ERROR")
    
    if [ "$REPLICATION_STATUS" != "ERROR" ]; then
        echo "Master replication status:"
        echo "$REPLICATION_STATUS"
    else
        echo "ERROR: Cannot connect to master database"
    fi
    
    echo "---"
    sleep 30
done
