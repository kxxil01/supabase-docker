{:ok, _} = Application.ensure_all_started(:supavisor)

{:ok, version} =
  case Supavisor.Repo.query!("select version()") do
    %{rows: [[ver]]} -> Supavisor.Helpers.parse_pg_version(ver)
    _ -> nil
  end

# Master database configuration
master_params = %{
  "external_id" => System.get_env("POOLER_TENANT_ID"),
  "db_host" => "db-master",
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

# Read-only replica configuration (if replica host is provided)
replica_host = System.get_env("POSTGRES_REPLICA_HOST")
replica_params = if replica_host do
  %{
    "external_id" => "#{System.get_env("POOLER_TENANT_ID")}_readonly",
    "db_host" => replica_host,
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
