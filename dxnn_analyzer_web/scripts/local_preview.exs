# Run with MIX_ENV=test mix run --no-start scripts/local_preview.exs.
# Supports a Docker-published port different from the internal HTTP port.
port = String.to_integer(System.get_env("DXNN_PREVIEW_PORT", "4010"))
public_port = String.to_integer(System.get_env("DXNN_PREVIEW_PUBLIC_PORT", "49417"))
true = port in 1..65535 and public_port in 1..65535

Application.put_env(:dxnn_analyzer_web, :start_services, true)
config = Application.get_env(:dxnn_analyzer_web, DxnnAnalyzerWeb.Endpoint)

Application.put_env(
  :dxnn_analyzer_web,
  DxnnAnalyzerWeb.Endpoint,
  Keyword.merge(config,
    server: true,
    http: [ip: {0, 0, 0, 0}, port: port],
    url: [host: "localhost", port: public_port],
    check_origin: ["http://localhost:#{public_port}", "http://127.0.0.1:#{public_port}"]
  )
)

{:ok, _} = Application.ensure_all_started(:dxnn_analyzer_web)
Process.sleep(:infinity)
