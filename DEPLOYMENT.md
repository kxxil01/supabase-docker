# Deployment Guide: Multi-VM Supabase Setup

This guide provides the correct deployment sequence for setting up Supabase with PostgreSQL replication across two VMs.

## Prerequisites

- Two VMs with Docker and Docker Compose installed
- Network connectivity between VMs
- Sufficient resources (4GB+ RAM per VM recommended)

## Deployment Sequence

### Phase 1: Deploy Master (VM1) First

**Why VM1 first?**
- The replica needs an existing master to connect to
- Master must be running before replica initialization
- Replication setup requires master to be accessible

#### Step 1: Prepare VM1 (Master)

1. **Copy files to VM1:**
   ```bash
   # Copy entire project to VM1
   scp -r supabase-docker/ user@192.168.1.10:~/
   ```

2. **Configure environment on VM1:**
   ```bash
   # On VM1
   cd ~/supabase-docker
   cp .env.example .env
   
   # Edit .env with your settings
   nano .env
   ```

3. **Update .env for VM1:**
   ```bash
   # Database settings
   POSTGRES_PASSWORD=your-super-secret-and-long-postgres-password
   POSTGRES_HOST=db-master
   POSTGRES_DB=postgres
   POSTGRES_PORT=5432
   
   # Multi-VM settings
   POSTGRES_MASTER_HOST=192.168.1.10
   POSTGRES_REPLICA_HOST=192.168.1.11
   POSTGRES_REPLICATION_USER=replicator
   POSTGRES_REPLICATION_PASSWORD=replicator_pass
   
   # Supabase keys (generate your own)
   JWT_SECRET=your-super-secret-jwt-token-with-at-least-32-characters-long
   ANON_KEY=your-anon-key
   SERVICE_ROLE_KEY=your-service-role-key
   ```

#### Step 2: Deploy Master Stack

```bash
# On VM1
cd ~/supabase-docker

# Start the master stack
docker compose -f docker-compose-master.yml up -d

# Wait for services to be healthy (2-3 minutes)
docker compose -f docker-compose-master.yml ps
```

#### Step 3: Verify Master is Running

```bash
# Check master database is accessible
docker exec supabase-db-master psql -U postgres -c "SELECT version();"

# Verify replication setup
docker exec supabase-db-master psql -U postgres -c "SELECT * FROM pg_replication_slots;"

# Check if replication user exists
docker exec supabase-db-master psql -U postgres -c "SELECT rolname FROM pg_roles WHERE rolname = 'replicator';"
```

### Phase 2: Deploy Replica (VM2) Second

**Why VM2 second?**
- Replica needs to connect to running master
- Base backup requires master to be accessible
- Replication stream starts immediately after setup

#### Step 4: Prepare VM2 (Replica)

1. **Copy replica files to VM2:**
   ```bash
   # Copy only replica-specific files
   scp docker-compose-replica.yml user@192.168.1.11:~/
   scp -r volumes/ user@192.168.1.11:~/
   scp .env user@192.168.1.11:~/
   ```

2. **Configure environment on VM2:**
   ```bash
   # On VM2
   nano .env
   
   # Update master host to point to VM1
   POSTGRES_MASTER_HOST=192.168.1.10
   POSTGRES_REPLICA_HOST=192.168.1.11
   
   # Keep same passwords as VM1
   POSTGRES_PASSWORD=your-super-secret-and-long-postgres-password
   POSTGRES_REPLICATION_PASSWORD=replicator_pass
   ```

#### Step 5: Deploy Replica

```bash
# On VM2
docker compose -f docker-compose-replica.yml up -d

# Monitor replica initialization (this may take a few minutes)
docker logs supabase-replica -f
```

#### Step 6: Verify Replication

```bash
# On VM2 - Check replica status
docker exec supabase-replica psql -U postgres -c "SELECT pg_is_in_recovery();"
# Should return: t (true - it's a replica)

# Check replication lag
docker exec supabase-replica-monitor /scripts/monitor-replica.sh

# On VM1 - Check replication connection
docker exec supabase-db-master psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

## Verification Steps

### 1. Test Basic Connectivity

```bash
# From VM1 to VM2
ping 192.168.1.11

# From VM2 to VM1  
ping 192.168.1.10

# Test PostgreSQL connectivity
psql -h 192.168.1.10 -U postgres -d postgres -c "SELECT 1;"
psql -h 192.168.1.11 -U postgres -d postgres -c "SELECT 1;"
```

### 2. Test Replication

```bash
# On VM1 (Master) - Insert test data
docker exec supabase-db-master psql -U postgres -c "
CREATE TABLE replication_test (id SERIAL, data TEXT, created_at TIMESTAMP DEFAULT NOW());
INSERT INTO replication_test (data) VALUES ('test from master');
"

# On VM2 (Replica) - Verify data replicated
docker exec supabase-replica psql -U postgres -c "SELECT * FROM replication_test;"
```

### 3. Test Pooler Routing

```bash
# Test writes through pooler (should go to master)
psql -h 192.168.1.10 -p 5432 -U postgres -d postgres -c "
INSERT INTO replication_test (data) VALUES ('via pooler');
"

# Verify on replica
psql -h 192.168.1.11 -U postgres -d postgres -c "SELECT COUNT(*) FROM replication_test;"
```

## Common Issues and Solutions

### Issue 1: Replica Can't Connect to Master

**Symptoms:**
- Replica logs show connection refused
- No replication slots active on master

**Solutions:**
```bash
# Check network connectivity
telnet 192.168.1.10 5432

# Check master is accepting connections
docker exec supabase-db-master psql -U postgres -c "SHOW listen_addresses;"

# Verify pg_hba.conf allows replication
docker exec supabase-db-master cat /var/lib/postgresql/data/pg_hba.conf | grep replication
```

### Issue 2: Authentication Failed

**Symptoms:**
- "password authentication failed for user replicator"

**Solutions:**
```bash
# Verify replication user exists on master
docker exec supabase-db-master psql -U postgres -c "SELECT * FROM pg_user WHERE usename = 'replicator';"

# Check password matches in .env files
grep POSTGRES_REPLICATION_PASSWORD .env

# Recreate replication user if needed
docker exec supabase-db-master psql -U postgres -f /docker-entrypoint-initdb.d/replication-setup.sql
```

### Issue 3: Pooler Not Routing Correctly

**Symptoms:**
- Writes fail after failover
- Pooler logs show connection errors

**Solutions:**
```bash
# Check pooler logs
docker logs supabase-pooler --tail 50

# Verify environment variables
docker exec supabase-pooler env | grep POSTGRES

# Test master detection manually
./test-pooler.sh
```

## Scaling and Maintenance

### Adding More Replicas

To add additional read replicas:

1. **Create new VM (VM3)**
2. **Copy replica configuration**
3. **Update environment variables**
4. **Deploy using same replica process**

### Maintenance Windows

For updates:

1. **Update replica first** (no downtime)
2. **Failover to replica** (promote to master)
3. **Update original master** (now replica)
4. **Failback if needed**

## Security Considerations

### Network Security

```bash
# Restrict PostgreSQL access to specific IPs
# Edit pg_hba.conf to replace 0.0.0.0/0 with specific CIDR blocks

# Use SSL connections (recommended for production)
# Add SSL certificates and update connection strings

# Firewall rules
sudo ufw allow from 192.168.1.10 to any port 5432
sudo ufw allow from 192.168.1.11 to any port 5432
```

### Credential Management

```bash
# Use strong passwords
# Store credentials in secure key management
# Rotate passwords regularly
# Use SSL certificates for authentication
```

## Monitoring Setup

### Health Checks

```bash
# Add to crontab for continuous monitoring
*/5 * * * * /home/user/supabase-docker/test-pooler.sh > /var/log/supabase-health.log 2>&1
```

### Alerting

```bash
# Set up alerts for:
# - Replication lag > 5 seconds
# - Master/replica connectivity issues
# - Pooler routing failures
# - Disk space < 20%
```

## Backup Strategy

### Automated Backups

```bash
# Daily backup script
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
docker exec supabase-db-master pg_dump -U postgres postgres > backup_${DATE}.sql

# Keep last 7 days
find /backups -name "backup_*.sql" -mtime +7 -delete
```

This deployment sequence ensures proper initialization order and successful replication setup between your VMs.
