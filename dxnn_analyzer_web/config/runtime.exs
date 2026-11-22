import Config

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      "dxnn_analyzer_default_secret_key_base_for_docker_change_in_production_min_64_chars"

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")
  # A local dashboard is reachable through either loopback hostname. Keep the
  # exact scheme/port allowlist so LiveView connects through both URLs.
  origins =
    if host in ["localhost", "127.0.0.1"] do
      ["http://localhost:#{port}", "http://127.0.0.1:#{port}"]
    else
      true
    end

  config :dxnn_analyzer_web, DxnnAnalyzerWeb.Endpoint,
    url: [host: host, port: port, scheme: "http"],
    check_origin: origins,
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    server: true
end
