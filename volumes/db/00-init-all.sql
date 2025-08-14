-- Comprehensive Supabase Database Initialization Script
-- This script ensures all databases, users, and configurations are created properly
-- Runs during PostgreSQL container initialization

-- Set variables from environment
\set pguser `echo "$POSTGRES_USER"`
\set pgpass `echo "$POSTGRES_PASSWORD"`
\set jwt_secret `echo "$JWT_SECRET"`

-- Create _supabase database for analytics
CREATE DATABASE _supabase WITH OWNER :pguser;

-- Create essential Supabase roles and users
-- These are required for all Supabase services to function

-- Create authenticator role (used by PostgREST)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'authenticator') THEN
        CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD :'pgpass';
    END IF;
END
$$;

-- Create supabase_auth_admin role
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'supabase_auth_admin') THEN
        CREATE ROLE supabase_auth_admin NOINHERIT CREATEROLE LOGIN PASSWORD :'pgpass';
    END IF;
END
$$;

-- Create supabase_admin role (superuser for Supabase operations)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'supabase_admin') THEN
        CREATE ROLE supabase_admin SUPERUSER CREATEDB CREATEROLE REPLICATION BYPASSRLS LOGIN PASSWORD :'pgpass';
    END IF;
END
$$;

-- Create supabase_storage_admin role
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'supabase_storage_admin') THEN
        CREATE ROLE supabase_storage_admin NOINHERIT CREATEROLE LOGIN PASSWORD :'pgpass';
    END IF;
END
$$;

-- Create anonymous and authenticated roles (no login)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN;
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN;
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN BYPASSRLS;
    END IF;
END
$$;

-- Create supabase_read_only_user
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'supabase_read_only_user') THEN
        CREATE ROLE supabase_read_only_user NOINHERIT LOGIN PASSWORD :'pgpass';
    END IF;
END
$$;

-- Create dashboard_user
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'dashboard_user') THEN
        CREATE ROLE dashboard_user NOSUPERUSER CREATEDB CREATEROLE REPLICATION LOGIN PASSWORD :'pgpass';
    END IF;
END
$$;

-- Create replication user for multi-VM setup
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replicator') THEN
        CREATE ROLE replicator REPLICATION LOGIN PASSWORD 'replicator_pass';
    END IF;
END
$$;

-- Grant necessary permissions
GRANT anon, authenticated, service_role TO authenticator;
GRANT authenticator TO supabase_auth_admin;
GRANT supabase_admin TO supabase_auth_admin;
GRANT supabase_storage_admin TO supabase_auth_admin;

-- Grant database permissions
GRANT ALL ON DATABASE postgres TO supabase_admin;
GRANT ALL ON DATABASE _supabase TO supabase_admin;
GRANT CONNECT ON DATABASE postgres TO anon, authenticated, service_role;
GRANT CONNECT ON DATABASE _supabase TO supabase_admin;

-- Create archive directory for WAL archiving
\! mkdir -p /var/lib/postgresql/archive
\! chown postgres:postgres /var/lib/postgresql/archive

-- Log successful initialization
\echo 'Supabase database initialization completed successfully'
