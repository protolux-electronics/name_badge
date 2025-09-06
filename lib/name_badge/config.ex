defmodule NameBadge.Config do
  @config_file "/data/config.json"

  def load_config() do
    @config_file
    |> File.read()
    |> case do
      {:ok, config_json} -> :json.decode(config_json)
      {:error, _reason} -> nil
    end
  end

  def store_config(config) do
    config_json = :json.encode(config)
    File.write(@config_file, config_json, [:write])
  end
end
