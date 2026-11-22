defmodule DxnnAnalyzerWeb.LocalOriginTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias DxnnAnalyzerWeb.Endpoint

  setup do
    previous = Map.new(~w(PHX_HOST PORT), &{&1, System.get_env(&1)})
    System.put_env(%{"PHX_HOST" => "localhost", "PORT" => "49417"})

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)

    start_supervised!({Phoenix.PubSub, name: DxnnAnalyzerWeb.PubSub})
    start_supervised!(Endpoint)
    :ok
  end

  @tag capture_log: true
  test "production local dashboard accepts both loopback origins on the configured port only" do
    config = Config.Reader.read!(Path.expand("../config/runtime.exs", __DIR__), env: :prod)

    origins =
      config
      |> Keyword.fetch!(:dxnn_analyzer_web)
      |> Keyword.fetch!(Endpoint)
      |> Keyword.fetch!(:check_origin)

    for origin <- ["http://localhost:49417", "http://127.0.0.1:49417"] do
      conn = Plug.Test.conn(:get, "/live/websocket") |> put_req_header("origin", origin)

      checked =
        Phoenix.Socket.Transport.check_origin(conn, Phoenix.LiveView.Socket, Endpoint,
          check_origin: origins
        )

      refute checked.halted
    end

    for origin <- [
          "http://127.0.0.1:49418",
          "http://localhost.evil.test:49417",
          "http://evil.test:49417"
        ] do
      conn = Plug.Test.conn(:get, "/live/websocket") |> put_req_header("origin", origin)

      assert %{halted: true, status: 403} =
               Phoenix.Socket.Transport.check_origin(conn, Phoenix.LiveView.Socket, Endpoint,
                 check_origin: origins
               )
    end
  end

  test "public deployments continue to use their configured hostname" do
    System.put_env("PHX_HOST", "dashboard.example.com")
    config = Config.Reader.read!(Path.expand("../config/runtime.exs", __DIR__), env: :prod)
    endpoint = config |> Keyword.fetch!(:dxnn_analyzer_web) |> Keyword.fetch!(Endpoint)
    assert Keyword.fetch!(endpoint, :check_origin) == true
    assert endpoint[:url][:host] == "dashboard.example.com"
  end
end
