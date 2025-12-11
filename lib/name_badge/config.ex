defmodule NameBadge.Config do
  def load_config() do
    config_file()
    |> File.read()
    |> case do
      {:ok, config_json} -> :json.decode(config_json)
      {:error, _reason} -> %{}
    end
  end

  def store_config(config) do
    config_json = :json.encode(config)
    File.write(config_file(), config_json, [:write])
  end

  if Mix.target() == :host do
    def config_file do
      System.tmp_dir!()
      |> Path.join("config.json")
    end
  else
    def config_file, do: "/data/config.json"
  end
end
