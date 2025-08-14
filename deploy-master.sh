#!/bin/bash
set -e

# Supabase Master VM Deployment Script
# Ensures flawless deployment with proper initialization

echo "🚀 Starting Supabase Master VM Deployment..."

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "❌ Error: .env file not found!"
    echo "Please copy .env.example to .env and configure your settings"
    exit 1
fi

# Source environment variables
source .env

# Validate required environment variables
REQUIRED_VARS=(
    "POSTGRES_PASSWORD"
    "JWT_SECRET"
    "ANON_KEY"
    "SERVICE_ROLE_KEY"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Error: Required environment variable $var is not set in .env"
        exit 1
    fi
done

echo "✅ Environment variables validated"

# Stop any existing containers
echo "🛑 Stopping existing containers..."
docker compose -f docker-compose-master.yml down 2>/dev/null || true

# Remove existing database volume to ensure clean initialization
echo "🗑️  Removing existing database volume for clean initialization..."
docker volume rm supabase-master_db-config 2>/dev/null || true

# Pull latest images
echo "📦 Pulling latest Docker images..."
docker compose -f docker-compose-master.yml pull

# Start the services
echo "🚀 Starting Supabase Master services..."
docker compose -f docker-compose-master.yml up -d

# Wait for database to be ready
echo "⏳ Waiting for database to initialize..."
timeout=300  # 5 minutes timeout
counter=0

while [ $counter -lt $timeout ]; do
    if docker exec supabase-db-master pg_isready -U postgres >/dev/null 2>&1; then
        echo "✅ Database is ready!"
        break
    fi
    
    if [ $((counter % 10)) -eq 0 ]; then
        echo "   Still waiting for database... ($counter/$timeout seconds)"
    fi
    
    sleep 1
    counter=$((counter + 1))
done

if [ $counter -eq $timeout ]; then
    echo "❌ Database failed to start within $timeout seconds"
    echo "📋 Database logs:"
    docker logs supabase-db-master --tail 20
    exit 1
fi

# Verify _supabase database was created
echo "🔍 Verifying _supabase database creation..."
if docker exec supabase-db-master psql -U postgres -lqt | cut -d \| -f 1 | grep -qw "_supabase"; then
    echo "✅ _supabase database created successfully"
else
    echo "❌ _supabase database was not created"
    exit 1
fi

# Verify essential users exist
echo "🔍 Verifying essential users..."
REQUIRED_USERS=("authenticator" "supabase_auth_admin" "supabase_admin")
for user in "${REQUIRED_USERS[@]}"; do
    if docker exec supabase-db-master psql -U postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='$user'" | grep -q 1; then
        echo "✅ User $user exists"
    else
        echo "❌ User $user does not exist"
        exit 1
    fi
done

# Wait for all services to be healthy
echo "⏳ Waiting for all services to be healthy..."
sleep 30

# Check service health
echo "🔍 Checking service health..."
FAILED_SERVICES=()

SERVICES=("supabase-studio" "supabase-kong" "supabase-auth" "supabase-rest" "supabase-realtime" "supabase-storage" "supabase-db-master" "supabase-analytics")

for service in "${SERVICES[@]}"; do
    if docker ps --filter "name=$service" --filter "status=running" | grep -q "$service"; then
        echo "✅ $service is running"
    else
        echo "❌ $service is not running"
        FAILED_SERVICES+=("$service")
    fi
done

if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
    echo "❌ Some services failed to start: ${FAILED_SERVICES[*]}"
    echo "📋 Checking logs for failed services..."
    for service in "${FAILED_SERVICES[@]}"; do
        echo "--- $service logs ---"
        docker logs "$service" --tail 10 2>/dev/null || echo "No logs available"
    done
    exit 1
fi

# Final verification
echo "🔍 Final verification..."
echo "📊 Service Status:"
docker compose -f docker-compose-master.yml ps

echo ""
echo "🎉 Supabase Master VM deployed successfully!"
echo ""
echo "📋 Access Information:"
echo "   Studio:    http://localhost:3000"
echo "   API:       http://localhost:8000"
echo "   Database:  localhost:5432"
echo ""
echo "🔧 Next Steps:"
echo "   1. Access Supabase Studio at http://localhost:3000"
echo "   2. Deploy replica VM using docker-compose-replica.yml"
echo "   3. Run ./test-pooler.sh to verify pooler configuration"
echo "   4. Run ./test-failover.sh to test automatic failover"
echo ""
echo "✅ Deployment completed successfully!"
