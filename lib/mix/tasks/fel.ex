defmodule Mix.Tasks.Fel do
  use Mix.Task

  @shortdoc "Downloads USB FEL loaders and launches the trellis board via FEL"

  @moduledoc """
  Downloads the latest USB FEL loaders release, unzips it under `_build/fel/`,
  and runs `launch.sh trellis` from `_build/fel/release/`.

      mix fel
  """

  @release_url "https://github.com/gworkman/usb_fel_loaders/releases/download/v0.1.0/release.zip"
  @dest_dir "_build/fel"
  @zip_path "_build/fel/release.zip"

  @impl Mix.Task
  def run(_args) do
    File.mkdir_p!(@dest_dir)

    Mix.shell().info("Downloading USB FEL loaders from #{@release_url}...")
    download!(@release_url, @zip_path)

    Mix.shell().info("Unzipping #{@zip_path}...")
    unzip!(@zip_path, @dest_dir)

    Mix.shell().info("Launching trellis via FEL...")
    launch!(Path.join(@dest_dir, "release"))
  end

  defp download!(url, dest) do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    case :httpc.request(:get, {String.to_charlist(url), []}, [ssl: ssl_opts()], body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        File.write!(dest, body)

      {:ok, {{_, status, _}, _headers, _body}} ->
        Mix.raise("Download failed with HTTP status #{status}")

      {:error, reason} ->
        Mix.raise("Download failed: #{inspect(reason)}")
    end
  end

  defp unzip!(zip_path, dest_dir) do
    zip_path
    |> String.to_charlist()
    |> :zip.unzip(cwd: String.to_charlist(dest_dir))
    |> case do
      {:ok, _files} -> :ok
      {:error, reason} -> Mix.raise("Unzip failed: #{inspect(reason)}")
    end
  end

  defp launch!(dest_dir) do
    dest_dir = Path.expand(dest_dir)
    script = Path.join(dest_dir, "launch.sh")
    File.chmod!(script, 0o755)

    bash =
      case :os.find_executable(~c"bash") do
        false -> Mix.raise("bash not found in PATH")
        path -> List.to_string(path)
      end

    port =
      Port.open({:spawn_executable, bash}, [
        :binary,
        :stderr_to_stdout,
        {:args, [script, "trellis"]},
        {:cd, dest_dir}
      ])

    stream_port(port)
  end

  defp stream_port(port) do
    receive do
      {^port, {:data, data}} ->
        IO.write(data)
        stream_port(port)

      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, status}} ->
        Mix.raise("launch.sh exited with status #{status}")
    end
  end

  defp ssl_opts do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end
end
