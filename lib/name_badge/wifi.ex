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

      {:ok, "rtw_8723du"} ->
        pull_up(state)

      _error ->
        Logger.warning("NameBadge.Wifi error: no supported wifi modules found")
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

  @impl PowerManager
  def handle_info(_message, state), do: {:noreply, state}

  defp pull_down(state) do
    :ok = Circuits.GPIO.write_one(state.gpio, 0)
  end

  defp pull_up(state) do
    :ok = Circuits.GPIO.write_one(state.gpio, 1)
  end

  def wifi_module() do
    usb_drivers =
      Path.wildcard("/sys/bus/usb/devices/*/uevent")
      |> Enum.map(&read_usb_info/1)
      |> Enum.filter(&Map.has_key?(&1, "DRIVER"))
      |> Enum.map(&Map.get(&1, "DRIVER"))
      |> Enum.uniq()

    cond do
      Enum.any?(usb_drivers, &(&1 == "rtl8xxxu")) ->
        {:ok, "rtl8xxxu"}

      Enum.any?(usb_drivers, &(&1 == "rtw_8723du")) ->
        {:ok, "rtw_8723du"}

      true ->
        {:error, :no_supported_modules}
    end
  end

  defp read_usb_info(uevent_path) do
    File.read!(uevent_path)
    |> parse_kv_config()
  end

  defp parse_kv_config(contents) do
    contents
    |> String.split("\n")
    |> Enum.flat_map(&parse_kv/1)
    |> Enum.into(%{})
  end

  defp parse_kv(""), do: []
  defp parse_kv(<<"#", _rest::binary>>), do: []

  defp parse_kv(key_equals_value) do
    [key, value] = String.split(key_equals_value, "=", parts: 2, trim: true)
    [{key, value}]
  end
end
