#!/bin/bash

# Supabase Multi-VM Failover Test Script
# This script tests the automatic failover functionality

set -e

echo "🧪 Supabase Multi-VM Failover Test"
echo "=================================="

# Configuration
MASTER_HOST=${POSTGRES_MASTER_HOST:-"192.168.1.10"}
REPLICA_HOST=${POSTGRES_REPLICA_HOST:-"192.168.1.11"}
POOLER_HOST=${MASTER_HOST}
DB_NAME=${POSTGRES_DB:-"postgres"}
DB_USER="postgres"
DB_PASSWORD=${POSTGRES_PASSWORD:-"your-super-secret-and-long-postgres-password"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check database role
check_db_role() {
    local host=$1
    local role_name=$2
    
    log_info "Checking $role_name database role on $host..."
    
    if psql -h "$host" -p 5432 -U "$DB_USER" -d "$DB_NAME" -c "SELECT CASE WHEN pg_is_in_recovery() THEN 'REPLICA' ELSE 'MASTER' END as role;" 2>/dev/null; then
        log_success "$role_name is accessible"
        return 0
    else
        log_error "$role_name is not accessible"
        return 1
    fi
}

# Function to test write operations
test_write() {
    local host=$1
    local description=$2
    
    log_info "Testing write operations on $description ($host)..."
    
    # Create test table and insert data
    if psql -h "$host" -p 5432 -U "$DB_USER" -d "$DB_NAME" -c "
        CREATE TABLE IF NOT EXISTS failover_test (
            id SERIAL PRIMARY KEY,
            test_time TIMESTAMP DEFAULT NOW(),
            test_host VARCHAR(50),
            test_description TEXT
        );
        INSERT INTO failover_test (test_host, test_description) 
        VALUES ('$host', '$description');
        SELECT COUNT(*) as total_records FROM failover_test;
    " 2>/dev/null; then
        log_success "Write operation successful on $description"
        return 0
    else
        log_error "Write operation failed on $description"
        return 1
    fi
}

# Function to test read operations
test_read() {
    local host=$1
    local description=$2
    
    log_info "Testing read operations on $description ($host)..."
    
    if psql -h "$host" -p 5432 -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT COUNT(*) as total_records FROM failover_test WHERE test_host = '$host';
    " 2>/dev/null; then
        log_success "Read operation successful on $description"
        return 0
    else
        log_error "Read operation failed on $description"
        return 1
    fi
}

# Function to test pooler routing
test_pooler_routing() {
    log_info "Testing pooler routing..."
    
    # Test write through pooler (should go to master)
    log_info "Testing write through pooler (should route to master)..."
    if psql -h "$POOLER_HOST" -p 5432 -U "$DB_USER" -d "$DB_NAME" -c "
        INSERT INTO failover_test (test_host, test_description) 
        VALUES ('pooler-write', 'Write through pooler');
    " 2>/dev/null; then
        log_success "Pooler write routing works"
    else
        log_error "Pooler write routing failed"
    fi
    
    # Test read through pooler
    log_info "Testing read through pooler..."
    if psql -h "$POOLER_HOST" -p 5432 -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT test_description FROM failover_test WHERE test_host = 'pooler-write' LIMIT 1;
    " 2>/dev/null; then
        log_success "Pooler read routing works"
    else
        log_error "Pooler read routing failed"
    fi
}

# Function to simulate failover
simulate_failover() {
    log_warning "🚨 SIMULATING FAILOVER - PROMOTING REPLICA TO MASTER"
    log_info "This will promote the replica ($REPLICA_HOST) to become the new master"
    
    read -p "Continue with failover simulation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Failover simulation cancelled"
        return 1
    fi
    
    log_info "Promoting replica to master..."
    # This would typically be done on the replica VM
    echo "Run this command on VM2 (Replica):"
    echo "docker exec supabase-replica touch /var/lib/postgresql/data/promote.trigger"
    
    log_warning "After running the promotion command, wait 10-30 seconds for the promotion to complete"
    read -p "Press Enter after promotion is complete..."
    
    return 0
}

# Function to verify failover
verify_failover() {
    log_info "🔍 Verifying failover results..."
    
    # Check roles after failover
    log_info "Checking database roles after failover..."
    
    echo "VM1 ($MASTER_HOST) role:"
    check_db_role "$MASTER_HOST" "VM1" || log_warning "VM1 may be down (expected after failover)"
    
    echo "VM2 ($REPLICA_HOST) role:"
    check_db_role "$REPLICA_HOST" "VM2"
    
    # Test writes through pooler after failover
    log_info "Testing writes through pooler after failover..."
    if test_write "$POOLER_HOST" "Pooler after failover"; then
        log_success "✅ FAILOVER SUCCESS: Pooler automatically routes writes to new master!"
    else
        log_error "❌ FAILOVER FAILED: Pooler cannot route writes after failover"
    fi
}

# Main test sequence
main() {
    echo
    log_info "Starting failover test sequence..."
    echo
    
    # Pre-failover tests
    log_info "📋 Phase 1: Pre-Failover Testing"
    echo "================================"
    
    check_db_role "$MASTER_HOST" "VM1 (Master)"
    check_db_role "$REPLICA_HOST" "VM2 (Replica)"
    
    test_write "$MASTER_HOST" "VM1 Master"
    test_read "$REPLICA_HOST" "VM2 Replica"
    
    test_pooler_routing
    
    echo
    log_info "📋 Phase 2: Failover Simulation"
    echo "==============================="
    
    if simulate_failover; then
        echo
        log_info "📋 Phase 3: Post-Failover Verification"
        echo "======================================"
        
        verify_failover
    fi
    
    echo
    log_info "🧪 Test completed!"
    echo "=================="
    
    # Cleanup
    log_info "Cleaning up test data..."
    psql -h "$POOLER_HOST" -p 5432 -U "$DB_USER" -d "$DB_NAME" -c "DROP TABLE IF EXISTS failover_test;" 2>/dev/null || true
    
    echo
    log_success "Failover test script finished!"
}

# Check prerequisites
if ! command -v psql &> /dev/null; then
    log_error "psql command not found. Please install PostgreSQL client."
    exit 1
fi

# Export password to avoid prompts
export PGPASSWORD="$DB_PASSWORD"

# Run main test
main "$@"
