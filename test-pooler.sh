#!/bin/bash

# Supabase Pooler Master Detection Test Script
# Tests the dynamic master detection functionality

set -e

echo "🔍 Supabase Pooler Master Detection Test"
echo "========================================"

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
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check which database is master
check_master_status() {
    local host=$1
    local name=$2
    
    log_info "Checking master status on $name ($host)..."
    
    local result=$(psql -h "$host" -p 5432 -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT CASE WHEN pg_is_in_recovery() THEN 'REPLICA' ELSE 'MASTER' END;" 2>/dev/null | xargs)
    
    if [ "$result" = "MASTER" ]; then
        log_success "$name is MASTER ✅"
        return 0
    elif [ "$result" = "REPLICA" ]; then
        log_info "$name is REPLICA"
        return 1
    else
        log_error "$name is UNREACHABLE ❌"
        return 2
    fi
}

# Function to test pooler master detection logic
test_pooler_logic() {
    log_info "Testing pooler master detection logic..."
    
    # Create a simple Elixir script to test the detection logic
    cat > /tmp/test_master_detection.exs << 'EOF'
# Simulate the master detection logic
defmodule TestMasterDetector do
  def detect_master(master_host, replica_host, port, db, user, password) do
    hosts = [master_host, replica_host] |> Enum.filter(&(&1 != nil))
    
    IO.puts("Testing hosts: #{inspect(hosts)}")
    
    Enum.find(hosts, master_host, fn host ->
      IO.puts("Checking #{host}...")
      
      try do
        # Simulate connection check (we'll use psql instead of Postgrex for testing)
        {result, _} = System.cmd("psql", [
          "-h", host,
          "-p", to_string(port),
          "-U", user,
          "-d", db,
          "-t",
          "-c", "SELECT pg_is_in_recovery();"
        ], env: [{"PGPASSWORD", password}])
        
        case String.trim(result) do
          "f" -> 
            IO.puts("#{host} is MASTER ✅")
            true
          "t" -> 
            IO.puts("#{host} is REPLICA")
            false
          _ -> 
            IO.puts("#{host} returned unexpected result: #{result}")
            false
        end
      rescue
        error -> 
          IO.puts("#{host} connection failed: #{inspect(error)}")
          false
      end
    end)
  end
end

# Test the detection
master_host = System.get_env("MASTER_HOST", "192.168.1.10")
replica_host = System.get_env("REPLICA_HOST", "192.168.1.11")
port = String.to_integer(System.get_env("DB_PORT", "5432"))
db = System.get_env("DB_NAME", "postgres")
user = System.get_env("DB_USER", "postgres")
password = System.get_env("DB_PASSWORD", "password")

IO.puts("\n🔍 Running Master Detection Test")
IO.puts("================================")

detected_master = TestMasterDetector.detect_master(master_host, replica_host, port, db, user, password)

IO.puts("\n📊 Results:")
IO.puts("===========")
IO.puts("Detected Master: #{detected_master}")

if detected_master == master_host do
  IO.puts("✅ VM1 (#{master_host}) is the master")
elsif detected_master == replica_host do
  IO.puts("✅ VM2 (#{replica_host}) is the master")
else
  IO.puts("❌ No master detected or detection failed")
end
EOF

    # Run the test with environment variables
    MASTER_HOST="$MASTER_HOST" \
    REPLICA_HOST="$REPLICA_HOST" \
    DB_PORT="5432" \
    DB_NAME="$DB_NAME" \
    DB_USER="$DB_USER" \
    DB_PASSWORD="$DB_PASSWORD" \
    elixir /tmp/test_master_detection.exs
    
    # Clean up
    rm -f /tmp/test_master_detection.exs
}

# Function to test actual pooler configuration
test_pooler_config() {
    log_info "Testing actual pooler configuration..."
    
    # Check if pooler is running
    if docker ps | grep -q "supabase-pooler"; then
        log_success "Supabase pooler is running"
        
        # Check pooler logs for master detection
        log_info "Checking pooler logs for master detection..."
        docker logs supabase-pooler --tail 20 2>/dev/null | grep -i "master\|tenant\|host" || log_info "No relevant logs found"
        
        # Test pooler health
        log_info "Testing pooler health endpoint..."
        if curl -s "http://$POOLER_HOST:4000/api/health" > /dev/null; then
            log_success "Pooler health check passed"
        else
            log_error "Pooler health check failed"
        fi
        
    else
        log_error "Supabase pooler is not running"
    fi
}

# Function to test connection routing
test_connection_routing() {
    log_info "Testing connection routing through pooler..."
    
    # Test write operation (should go to master)
    log_info "Testing write operation routing..."
    if psql -h "$POOLER_HOST" -p 5432 -U "$DB_USER" -d "$DB_NAME" -c "
        CREATE TABLE IF NOT EXISTS pooler_test (
            id SERIAL PRIMARY KEY,
            test_time TIMESTAMP DEFAULT NOW(),
            operation_type VARCHAR(10)
        );
        INSERT INTO pooler_test (operation_type) VALUES ('WRITE');
        SELECT 'Write operation successful' as result;
    " 2>/dev/null; then
        log_success "Write operation through pooler successful"
    else
        log_error "Write operation through pooler failed"
    fi
    
    # Test read operation
    log_info "Testing read operation routing..."
    if psql -h "$POOLER_HOST" -p 5432 -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT COUNT(*) as write_count FROM pooler_test WHERE operation_type = 'WRITE';
    " 2>/dev/null; then
        log_success "Read operation through pooler successful"
    else
        log_error "Read operation through pooler failed"
    fi
    
    # Clean up
    psql -h "$POOLER_HOST" -p 5432 -U "$DB_USER" -d "$DB_NAME" -c "DROP TABLE IF EXISTS pooler_test;" 2>/dev/null || true
}

# Main test function
main() {
    echo
    log_info "Starting pooler master detection tests..."
    echo
    
    # Export password
    export PGPASSWORD="$DB_PASSWORD"
    
    # Test 1: Check current master/replica status
    log_info "📋 Test 1: Database Role Detection"
    echo "=================================="
    
    check_master_status "$MASTER_HOST" "VM1"
    VM1_STATUS=$?
    
    check_master_status "$REPLICA_HOST" "VM2"
    VM2_STATUS=$?
    
    if [ $VM1_STATUS -eq 0 ]; then
        log_success "Current master: VM1 ($MASTER_HOST)"
    elif [ $VM2_STATUS -eq 0 ]; then
        log_success "Current master: VM2 ($REPLICA_HOST)"
    else
        log_error "No master detected!"
    fi
    
    echo
    
    # Test 2: Pooler master detection logic
    log_info "📋 Test 2: Pooler Master Detection Logic"
    echo "========================================"
    
    if command -v elixir &> /dev/null; then
        test_pooler_logic
    else
        log_error "Elixir not found. Skipping logic test."
        log_info "Install Elixir to test the detection logic: brew install elixir"
    fi
    
    echo
    
    # Test 3: Actual pooler configuration
    log_info "📋 Test 3: Pooler Configuration Test"
    echo "==================================="
    
    test_pooler_config
    
    echo
    
    # Test 4: Connection routing
    log_info "📋 Test 4: Connection Routing Test"
    echo "================================="
    
    test_connection_routing
    
    echo
    log_success "Pooler master detection tests completed!"
}

# Check prerequisites
if ! command -v psql &> /dev/null; then
    log_error "psql command not found. Please install PostgreSQL client."
    exit 1
fi

if ! command -v docker &> /dev/null; then
    log_error "docker command not found. Please install Docker."
    exit 1
fi

# Run tests
main "$@"
