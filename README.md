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

**⚠️ IMPORTANT: Deploy in this exact order!**

### VM1 (Master)
```bash
git clone https://github.com/kxxil01/supabase-docker.git
cd supabase-docker
cp .env.example .env
# Edit .env with your configuration
docker compose -f docker-compose-master.yml up -d
```

### VM2 (Replica)
```bash
git clone https://github.com/kxxil01/supabase-docker.git
cd supabase-docker
cp .env.replica.example .env
# Edit .env with master VM IP (update IP addresses)
docker compose -f docker-compose-replica.yml up -d
```

## 🔧 Key Configuration

### VM1 Master (.env)
```bash
# Database
POSTGRES_PASSWORD=your-secure-password
POSTGRES_MASTER_HOST=192.168.1.10  # VM1 IP
POSTGRES_REPLICA_HOST=192.168.1.11  # VM2 IP

# Supabase Keys (generate new ones)
JWT_SECRET=your-jwt-secret
ANON_KEY=your-anon-key
SERVICE_ROLE_KEY=your-service-role-key
```

### VM2 Replica (.env)
```bash
# Database (MUST MATCH MASTER)
POSTGRES_PASSWORD=your-secure-password
POSTGRES_MASTER_HOST=192.168.1.10  # VM1 IP
POSTGRES_REPLICA_HOST=192.168.1.11  # VM2 IP
POSTGRES_REPLICATION_USER=replicator
POSTGRES_REPLICATION_PASSWORD=replicator_pass
```

## 📊 Access Points

- **Supabase Studio**: `http://vm1-ip:3000`
- **API Gateway**: `http://vm1-ip:8000`
- **Database**: `vm1-ip:5432` (via pooler with auto-failover)

## 🔄 Automatic Failover

Supavisor pooler automatically detects master/replica status and routes connections. If VM1 fails, promote VM2:
```bash
docker exec supabase-db-replica pg_promote
```

## 📋 Production Checklist

- [ ] Change default passwords
- [ ] Generate new JWT secrets  
- [ ] Configure firewall (ports 5432, 6543, 8000, 8443)
- [ ] Set up SSL certificates
- [ ] Configure backups
- [ ] Monitor replication: `docker exec supabase-db psql -U postgres -c "SELECT * FROM pg_stat_replication;"`

---
**⚡ Enterprise-grade Supabase with automatic failover**

For basic Supabase Docker setup, follow the steps [here](https://supabase.com/docs/guides/hosting/docker).
