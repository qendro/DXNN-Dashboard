defmodule DxnnAnalyzerWeb.S3ExplorerDownloadController do
  use DxnnAnalyzerWeb, :controller

  @download_root "/app/data/s3_downloads"
  @token_regex ~r/^[A-Za-z0-9_-]+$/

  def show(conn, %{"token" => token, "filename" => filename}) do
    with true <- Regex.match?(@token_regex, token),
         safe_filename <- sanitize_filename(filename),
         false <- safe_filename == "",
         {:ok, path} <- resolve_download_path(token, safe_filename),
         true <- File.regular?(path) do
      Phoenix.Controller.send_download(conn, {:file, path}, filename: safe_filename)
    else
      _ -> send_resp(conn, 404, "Download not found")
    end
  end

  defp resolve_download_path(token, filename) do
    expanded_root = Path.expand(@download_root)
    candidate = Path.expand(Path.join(@download_root, "#{token}_#{filename}"))

    if String.starts_with?(candidate, expanded_root <> "/") do
      {:ok, candidate}
    else
      {:error, :invalid_path}
    end
  end

  defp sanitize_filename(filename) do
    filename
    |> Path.basename()
    |> String.replace(~r/[^A-Za-z0-9._-]/, "_")
  end
end
