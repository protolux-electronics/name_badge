defmodule NameBadge.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @target Mix.target()

  @impl true
  def start(_type, _args) do
    setup_wifi()

    children =
      [
        # Children for all targets
        # Starts a worker by calling: NameBadge.Worker.start_link(arg)
        # {NameBadge.Worker, arg},
      ] ++ target_children(@target)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NameBadge.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # List all child processes to be supervised
  defp target_children(:host) do
    [
      # Children that only run on the host during development or test.
      # In general, prefer using `config/host.exs` for differences.
      #
      # Starts a worker by calling: Host.Worker.start_link(arg)
      # {Host.Worker, arg},
    ]
  end

  defp target_children(_target) do
    [
      {Registry, name: NameBadge.Registry, keys: :duplicate},
      button_spec(:button_1),
      button_spec(:button_2),
      NameBadge.Battery,
      NameBadge.Socket,
      NameBadge.Display,
      NameBadge.ScreenManager
    ]
  end

  defp button_spec(button_name, opts \\ []) do
    spec = {NameBadge.ButtonMonitor, Keyword.put(opts, :button, button_name)}
    Supervisor.child_spec(spec, id: button_name)
  end

  if Mix.target() == :host do
    defp setup_wifi(), do: :ok
  else
    defp setup_wifi() do
      kv = Nerves.Runtime.KV.get_all()

      if true?(kv["wifi_force"]) or not wlan0_configured?() do
        ssid = kv["wifi_ssid"]
        passphrase = kv["wifi_passphrase"]

        unless empty?(ssid) do
          _ = VintageNetWiFi.quick_configure(ssid, passphrase)
          :ok
        end
      end
    end

    defp wlan0_configured?() do
      VintageNet.get_configuration("wlan0") |> VintageNetWiFi.network_configured?()
    catch
      _, _ -> false
    end

    defp true?(""), do: false
    defp true?(nil), do: false
    defp true?("false"), do: false
    defp true?("FALSE"), do: false
    defp true?(_), do: true

    defp empty?(""), do: true
    defp empty?(nil), do: true
    defp empty?(_), do: false
  end
end
