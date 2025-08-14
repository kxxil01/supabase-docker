{:ok, _} = Application.ensure_all_started(:supavisor)

# Simple configuration - VM1 is always the master
master_host = System.get_env("POSTGRES_HOST", "db")
IO.puts("🔍 Master host: #{master_host} (VM1 is always master)")

{:ok, version} =
  case Supavisor.Repo.query!("select version()") do
    %{rows: [[ver]]} -> Supavisor.Helpers.parse_pg_version(ver)
    _ -> nil
  end

# Master database configuration (VM1 is always master)
master_params = %{
  "external_id" => System.get_env("POOLER_TENANT_ID"),
  "db_host" => master_host,
  "db_port" => System.get_env("POSTGRES_PORT"),
  "db_database" => "postgres",
  "require_user" => false,
  "default_max_clients" => System.get_env("POOLER_MAX_CLIENT_CONN"),
  "default_pool_size" => System.get_env("POOLER_DEFAULT_POOL_SIZE"),
  "default_parameter_status" => %{"server_version" => version},
  "users" => [%{
    "db_user" => "postgres",
    "db_password" => System.get_env("POSTGRES_PASSWORD"),
    "mode_type" => "transaction",
    "pool_size" => System.get_env("POOLER_DEFAULT_POOL_SIZE"),
    "is_manager" => true
  }]
}

# Replica connections should go directly to VM2, not through VM1 pooler
IO.puts("ℹ️  Replica connections handled directly to VM2 - no pooler tenant needed")

params = master_params

# Create master tenant
IO.puts("Creating master tenant with external_id: #{params["external_id"]}")
if !Supavisor.Tenants.get_tenant_by_external_id(params["external_id"]) do
  case Supavisor.Tenants.create_tenant(params) do
    {:ok, _tenant} -> 
      IO.puts("✅ Master tenant created successfully: #{params["external_id"]}")
    {:error, reason} -> 
      IO.puts("❌ Failed to create master tenant: #{inspect(reason)}")
  end
else
  IO.puts("ℹ️  Master tenant already exists: #{params["external_id"]}")
end

# No replica tenant needed - clients connect directly to VM2 for read operations
IO.puts("ℹ️  Read operations: Connect directly to VM2 replica (11.0.1.243:5432)")
IO.puts("ℹ️  Write operations: Use master tenant through pooler")
