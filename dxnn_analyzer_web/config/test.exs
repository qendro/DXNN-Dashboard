import Config

config :dxnn_analyzer_web, start_services: false

config :dxnn_analyzer_web, DxnnAnalyzerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("test_secret_key_base", 4),
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
