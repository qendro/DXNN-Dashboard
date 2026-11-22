defmodule DxnnAnalyzerWeb.GCPArtifactDownloadController do
  use DxnnAnalyzerWeb, :controller
  alias DxnnAnalyzerWeb.GCP.DxnnBridge

  def show(conn, %{"token" => token, "filename" => filename}) do
    if Regex.match?(~r/\A[0-9a-f]{32}\z/, token) and
         Regex.match?(~r/\Adxnn-[A-Za-z0-9_.-]+\.zip\z/, filename) do
      path = Path.join(DxnnBridge.exports_dir(), token <> ".zip")

      if File.regular?(path),
        do: send_download(conn, {:file, path}, filename: filename),
        else: send_resp(conn, 404, "Archive not found")
    else
      send_resp(conn, 404, "Archive not found")
    end
  end
end
