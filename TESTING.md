# Testing Guide: Supabase Multi-VM Failover

This guide provides comprehensive testing procedures for the Supabase multi-VM PostgreSQL replication setup with automatic failover.

## Prerequisites

- Both VMs (master and replica) are deployed and running
- PostgreSQL client (`psql`) installed on testing machine
- Docker installed (for container testing)
- Network access to both VMs
- Environment variables configured

## Test Scripts

### 1. Pooler Master Detection Test (`test-pooler.sh`)

Tests the dynamic master detection functionality:

```bash
chmod +x test-pooler.sh
./test-pooler.sh
```

**What it tests:**
- Database role detection (`pg_is_in_recovery()`)
- Pooler master detection logic
- Connection routing through pooler
- Pooler health and configuration

### 2. Complete Failover Test (`test-failover.sh`)

Tests the complete failover process:

```bash
chmod +x test-failover.sh
./test-failover.sh
```

**What it tests:**
- Pre-failover database roles
- Write/read operations on both VMs
- Pooler routing functionality
- Guided failover simulation
- Post-failover verification

## Manual Testing Procedures

### Test 1: Verify Initial Setup

1. **Check database roles:**
   ```bash
   # VM1 should be master
   psql -h 192.168.1.10 -U postgres -d postgres -c "SELECT CASE WHEN pg_is_in_recovery() THEN 'REPLICA' ELSE 'MASTER' END as role;"
   
   # VM2 should be replica
   psql -h 192.168.1.11 -U postgres -d postgres -c "SELECT CASE WHEN pg_is_in_recovery() THEN 'REPLICA' ELSE 'MASTER' END as role;"
   ```

2. **Test replication:**
   ```bash
   # Insert on master (VM1)
   psql -h 192.168.1.10 -U postgres -d postgres -c "CREATE TABLE test_replication (id SERIAL, data TEXT); INSERT INTO test_replication (data) VALUES ('test from master');"
   
   # Verify on replica (VM2)
   psql -h 192.168.1.11 -U postgres -d postgres -c "SELECT * FROM test_replication;"
   ```

### Test 2: Pooler Routing

1. **Test write through pooler:**
   ```bash
   # Should route to master
   psql -h 192.168.1.10 -p 5432 -U postgres -d postgres -c "INSERT INTO test_replication (data) VALUES ('via pooler');"
   ```

2. **Test read through pooler:**
   ```bash
   # Should work from either database
   psql -h 192.168.1.10 -p 5432 -U postgres -d postgres -c "SELECT COUNT(*) FROM test_replication;"
   ```

### Test 3: Failover Simulation

1. **Promote replica to master:**
   ```bash
   # On VM2, promote replica
   docker exec supabase-replica touch /var/lib/postgresql/data/promote.trigger
   ```

2. **Wait for promotion (10-30 seconds)**

3. **Verify role change:**
   ```bash
   # VM2 should now be master
   psql -h 192.168.1.11 -U postgres -d postgres -c "SELECT CASE WHEN pg_is_in_recovery() THEN 'REPLICA' ELSE 'MASTER' END as role;"
   ```

4. **Test writes through pooler:**
   ```bash
   # Should now route to VM2 automatically
   psql -h 192.168.1.10 -p 5432 -U postgres -d postgres -c "INSERT INTO test_replication (data) VALUES ('after failover');"
   ```

### Test 4: Monitoring and Logs

1. **Check replication status:**
   ```bash
   # On replica VM
   docker exec supabase-replica-monitor /scripts/monitor-replica.sh
   ```

2. **Check pooler logs:**
   ```bash
   # On master VM
   docker logs supabase-pooler --tail 50
   ```

3. **Check database logs:**
   ```bash
   # Master database logs
   docker logs supabase-db-master --tail 50
   
   # Replica database logs
   docker logs supabase-replica --tail 50
   ```

## Expected Results

### Normal Operation (VM1 Master, VM2 Replica)

- VM1: `pg_is_in_recovery()` returns `false` (MASTER)
- VM2: `pg_is_in_recovery()` returns `true` (REPLICA)
- Pooler routes writes to VM1
- Replication lag < 1 second
- All services healthy

### After Failover (VM2 Master, VM1 Down/Replica)

- VM2: `pg_is_in_recovery()` returns `false` (MASTER)
- VM1: Either down or `pg_is_in_recovery()` returns `true`
- Pooler automatically routes writes to VM2
- Applications continue working without changes
- Zero data loss

## Troubleshooting

### Common Issues

1. **Connection Refused**
   - Check VM network connectivity
   - Verify PostgreSQL is running
   - Check firewall settings

2. **Authentication Failed**
   - Verify `POSTGRES_PASSWORD` environment variable
   - Check `pg_hba.conf` configuration
   - Ensure user permissions

3. **Replication Lag**
   - Check network connectivity between VMs
   - Monitor `monitor-replica.sh` output
   - Verify replication user permissions

4. **Pooler Not Routing Correctly**
   - Check pooler logs: `docker logs supabase-pooler`
   - Verify environment variables
   - Test master detection logic

### Debug Commands

```bash
# Check pooler configuration
docker exec supabase-pooler cat /etc/pooler/pooler.exs

# Check database configuration
docker exec supabase-db-master cat /var/lib/postgresql/data/postgresql.conf

# Check replication status
docker exec supabase-db-master psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Check replica status
docker exec supabase-replica psql -U postgres -c "SELECT * FROM pg_stat_wal_receiver;"
```

## Performance Testing

### Load Testing

1. **Install pgbench:**
   ```bash
   # Usually comes with PostgreSQL client
   pgbench --version
   ```

2. **Initialize test database:**
   ```bash
   pgbench -h 192.168.1.10 -U postgres -i -s 10 postgres
   ```

3. **Run load test:**
   ```bash
   # Test writes (should go to master)
   pgbench -h 192.168.1.10 -U postgres -c 10 -j 2 -t 1000 postgres
   ```

4. **Test during failover:**
   ```bash
   # Start load test, then trigger failover
   pgbench -h 192.168.1.10 -U postgres -c 5 -j 1 -T 60 postgres &
   # Promote replica while test is running
   docker exec supabase-replica touch /var/lib/postgresql/data/promote.trigger
   ```

## Automated Testing

For continuous integration, create a test pipeline:

```bash
#!/bin/bash
# CI/CD test pipeline

set -e

echo "Running Supabase Multi-VM Tests..."

# Run pooler tests
./test-pooler.sh

# Run failover tests (automated)
export SKIP_INTERACTIVE=true
./test-failover.sh

echo "All tests passed ✅"
```

## Security Testing

1. **Test authentication:**
   ```bash
   # Should fail without password
   psql -h 192.168.1.10 -U postgres -d postgres -c "SELECT 1;" || echo "Authentication correctly required"
   ```

2. **Test network access:**
   ```bash
   # Test from different networks
   nmap -p 5432 192.168.1.10
   nmap -p 5432 192.168.1.11
   ```

3. **Test SSL connections (if enabled):**
   ```bash
   psql "sslmode=require host=192.168.1.10 user=postgres dbname=postgres"
   ```

## Conclusion

These tests ensure your Supabase multi-VM setup works correctly with automatic failover. Run them regularly to verify system health and after any configuration changes.

For production deployments, integrate these tests into your monitoring and alerting systems.
