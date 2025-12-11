defmodule NameBadge.Wifi do
  alias VintageNet.PowerManager

  require Logger

  @behaviour PowerManager

  @impl PowerManager
  def init(init_arg) do
    {:ok, Map.new(init_arg)}
  end

  @impl PowerManager
  def power_on(state) do
    case wifi_module() do
      {:ok, "rtl8xxxu"} ->
        pull_down(state)

      {:ok, driver} ->
        Logger.error("Unknown wifi module: #{driver}. Default to pull-up")
        pull_up(state)

      error ->
        Logger.error("NameBadge.Wifi error: #{inspect(error)}")
    end

    pull_down(state)
    {:ok, state, :timer.minutes(2)}
  end

  @impl PowerManager
  def start_powering_off(state) do
    {:ok, state, :timer.seconds(2)}
  end

  @impl PowerManager
  def power_off(state) do
    {:ok, state, :timer.seconds(2)}
  end

  defp pull_down(state) do
    :ok = Circuits.GPIO.write_one(state.gpio, 0)
  end

  defp pull_up(state) do
    :ok = Circuits.GPIO.write_one(state.gpio, 1)
  end

  defp wifi_module() do
    usb_info_path = "/sys/bus/usb/devices/2-1:1.0/uevent"

    case File.read(usb_info_path) do
      {:ok, usb_info} ->
        driver_name =
          usb_info
          |> String.split("DRIVER=")
          |> Enum.at(1)
          |> String.split("\n")
          |> hd()

        {:ok, driver_name}

      _error ->
        {:error, :unknown}
    end
  end
end
