#!/bin/bash
set -e

# Supabase Master Database Initialization Script
# Ensures all required databases, users, and directories are created

echo "Starting Supabase Master Database initialization..."

# Create archive directory for WAL archiving
mkdir -p /var/lib/postgresql/archive
chown postgres:postgres /var/lib/postgresql/archive
chmod 700 /var/lib/postgresql/archive

echo "Archive directory created successfully"

# Execute the original PostgreSQL entrypoint
exec docker-entrypoint.sh "$@"
