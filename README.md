# Supabase Docker with PostgreSQL Replication

Multi-VM PostgreSQL replication setup for Supabase with 1 Master + 1 Replica configuration.

## Architecture

- **VM1 (Master)**: Complete Supabase stack + PostgreSQL Master
- **VM2 (Replica)**: PostgreSQL Replica only
- **Network**: Cross-VM replication via streaming replication

## How It Works

**Master VM (VM1)**:
- Runs full Supabase stack (API, Auth, Storage, etc.)
- PostgreSQL master database with WAL enabled
- Accepts read/write operations
- Streams WAL to replica
- Supavisor pooler configured for master connections

**Replica VM (VM2)**:
- Runs PostgreSQL replica only
- Continuously receives WAL from master
- Read-only operations
- Automatic failover capability

## Pooler Configuration for Read/Write Splitting

The Supavisor pooler is configured with **automatic failover detection** to distinguish between master and replica:

**Connection Endpoints**:
- **Master (Read/Write)**: `postgresql://user:pass@master-ip:5432/db`
- **Replica (Read-Only)**: `postgresql://user:pass@master-ip:5432/db_readonly`

**How It Works**:

1. **Dynamic Master Detection**: Pooler queries both databases using `pg_is_in_recovery()` to detect which is actually the master
2. **Automatic Routing**: 
   - Primary tenant: Routes to whichever database is NOT in recovery (the actual master)
   - `_readonly` tenant: Routes to the other database (the actual replica)
3. **Failover Handling**: When VM2 becomes master after failover:
   - Pooler automatically detects VM2 as the new master
   - Write traffic gets routed to VM2 automatically
   - Read traffic gets routed to VM1 (if still available) or VM2
4. **Zero Downtime**: Applications continue working without connection string changes

## Files Structure

### Docker Compose Files

- `docker-compose-master.yml` - Full Supabase stack with PostgreSQL Master (VM1)
- `docker-compose-replica.yml` - PostgreSQL Replica only (VM2)

### PostgreSQL Configuration

- `volumes/db/postgresql-master.conf` - Master database configuration
- `volumes/db/postgresql-replica.conf` - Replica database configuration
- `volumes/db/pg_hba.conf` - Master authentication rules
- `volumes/db/pg_hba_replica.conf` - Replica authentication rules

### Setup Scripts

- `volumes/db/replication-setup.sql` - Creates replication user and slots
- `volumes/db/setup-replica.sh` - Automated replica initialization
- `volumes/db/monitor-replica.sh` - Replication lag monitoring

## Deployment Steps

### VM1 (Master) Setup

1. Copy all files to VM1
2. Configure environment variables in `.env`
3. Update IP addresses in configuration files
4. Deploy: `docker compose -f docker-compose-master.yml up -d`

### VM2 (Replica) Setup

1. Copy replica files to VM2
2. Configure environment variables in `.env`
3. Update `POSTGRES_MASTER_HOST` to VM1 IP address
4. Deploy: `docker compose -f docker-compose-replica.yml up -d`

## Environment Variables

Create `.env` file with these variables:

```bash
# Database
POSTGRES_PASSWORD=your_super_secret_password
POSTGRES_DB=postgres
POSTGRES_HOST=db-master
POSTGRES_PORT=5432

# Replication
POSTGRES_REPLICATION_USER=replicator
POSTGRES_REPLICATION_PASSWORD=replicator_pass
POSTGRES_MASTER_HOST=192.168.1.10  # VM1 IP address

# Supabase
ANON_KEY=your_anon_key
SERVICE_ROLE_KEY=your_service_role_key
JWT_SECRET=your_jwt_secret
JWT_EXPIRY=3600
```

## Key Benefits

🔥 **True High Availability** - If VM1 fails, VM2 can be promoted  
🚀 **Read Scaling** - Direct read queries to replica VM  
⚡ **Performance** - Separate resources for master/replica  
🛡️ **Fault Tolerance** - Physical separation of databases

## Monitoring

Use the monitoring script to check replication status:

```bash
# On VM2 (Replica)
docker exec supabase-replica-monitor /scripts/monitor-replica.sh
```

## Automatic Failover Process

**🚀 Zero-Downtime Failover**: The pooler automatically handles failover without manual intervention!

### When VM1 (Master) Fails:

1. **Promote Replica**: Create trigger file on VM2
   ```bash
   docker exec supabase-replica touch /var/lib/postgresql/data/promote.trigger
   ```

2. **Automatic Detection**: Pooler detects VM2 as the new master within seconds
   - Queries `pg_is_in_recovery()` on both databases
   - Routes writes to VM2 (new master) automatically
   - No application changes needed!

3. **Seamless Operation**: Applications continue working with same connection strings
   - Write operations → VM2 (new master)
   - Read operations → VM2 (or VM1 if recovered)

### Manual Failover (Alternative):

If you prefer manual control:
1. Promote replica as above
2. Update application connection strings to point to VM2
3. Restart Supabase services with new database host

**Recommendation**: Use automatic failover for production - it's faster and more reliable!

## Original Supabase Documentation

For basic Supabase Docker setup, follow the steps [here](https://supabase.com/docs/guides/hosting/docker).
