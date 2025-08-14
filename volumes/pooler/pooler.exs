{:ok, _} = Application.ensure_all_started(:supavisor)

# Function to detect which database is the actual master
defmodule MasterDetector do
  def detect_master(master_host, replica_host, port, db, user, password) do
    hosts = [master_host, replica_host] |> Enum.filter(&(&1 != nil))
    
    Enum.find(hosts, master_host, fn host ->
      try do
        {:ok, conn} = Postgrex.start_link(
          hostname: host,
          port: port,
          database: db,
          username: user,
          password: password
        )
        
        # Check if this database is NOT in recovery (i.e., it's the master)
        case Postgrex.query!(conn, "SELECT pg_is_in_recovery()", []) do
          %{rows: [[false]]} -> 
            GenServer.stop(conn)
            true  # This is the master
          _ -> 
            GenServer.stop(conn)
            false # This is a replica
        end
      rescue
        _ -> false # Connection failed, not the master
      end
    end)
  end
end

# Detect current master dynamically
master_host = System.get_env("POSTGRES_HOST", "db-master")
replica_host = System.get_env("POSTGRES_REPLICA_HOST")
port = String.to_integer(System.get_env("POSTGRES_PORT", "5432"))
db = System.get_env("POSTGRES_DB", "postgres")
user = "pgbouncer"
password = System.get_env("POSTGRES_PASSWORD")

current_master = MasterDetector.detect_master(master_host, replica_host, port, db, user, password)

{:ok, version} =
  case Supavisor.Repo.query!("select version()") do
    %{rows: [[ver]]} -> Supavisor.Helpers.parse_pg_version(ver)
    _ -> nil
  end

# Master database configuration (uses dynamically detected master)
master_params = %{
  "external_id" => System.get_env("POOLER_TENANT_ID"),
  "db_host" => current_master,
  "db_port" => System.get_env("POSTGRES_PORT"),
  "db_database" => System.get_env("POSTGRES_DB"),
  "require_user" => false,
  "auth_query" => "SELECT * FROM pgbouncer.get_auth($1)",
  "default_max_clients" => System.get_env("POOLER_MAX_CLIENT_CONN"),
  "default_pool_size" => System.get_env("POOLER_DEFAULT_POOL_SIZE"),
  "default_parameter_status" => %{"server_version" => version},
  "users" => [%{
    "db_user" => "pgbouncer",
    "db_password" => System.get_env("POSTGRES_PASSWORD"),
    "mode_type" => "transaction",
    "pool_size" => System.get_env("POOLER_DEFAULT_POOL_SIZE"),
    "is_manager" => true
  }]
}

# Read-only replica configuration (routes to whichever database is NOT the master)
current_replica = case current_master do
  ^master_host -> replica_host
  ^replica_host -> master_host
  _ -> replica_host
end

replica_params = if current_replica do
  %{
    "external_id" => "#{System.get_env("POOLER_TENANT_ID")}_readonly",
    "db_host" => current_replica,
    "db_port" => System.get_env("POSTGRES_PORT"),
    "db_database" => System.get_env("POSTGRES_DB"),
    "require_user" => false,
    "auth_query" => "SELECT * FROM pgbouncer.get_auth($1)",
    "default_max_clients" => System.get_env("POOLER_MAX_CLIENT_CONN"),
    "default_pool_size" => System.get_env("POOLER_DEFAULT_POOL_SIZE"),
    "default_parameter_status" => %{"server_version" => version},
    "users" => [%{
      "db_user" => "pgbouncer",
      "db_password" => System.get_env("POSTGRES_PASSWORD"),
      "mode_type" => "transaction",
      "pool_size" => System.get_env("POOLER_DEFAULT_POOL_SIZE"),
      "is_manager" => false
    }]
  }
else
  nil
end

params = master_params

# Create master tenant
if !Supavisor.Tenants.get_tenant_by_external_id(params["external_id"]) do
  {:ok, _} = Supavisor.Tenants.create_tenant(params)
end

# Create replica tenant if replica is configured
if replica_params && !Supavisor.Tenants.get_tenant_by_external_id(replica_params["external_id"]) do
  {:ok, _} = Supavisor.Tenants.create_tenant(replica_params)
end
