defmodule NameBadge.Wlan do
  @moduledoc """
  Handles changes in the WiFi/WLAN connection.
  """

  use GenServer

  @wlan0_property ["interface", "wlan0", "connection"]

  def init(_args) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def connected?() do
    GenServer.call(__MODULE__, :get_connected)
  end

  # Callbacks

  def start_link(_args) do
    VintageNet.subscribe(@wlan0_property)

    # Connect to the WiFi with a 2s delay
    Process.send_after(self(), :connect, :timer.seconds(2))

    {:ok, %{connected?: false}}
  end

  def handle_call(:get_connected, state) do
    {:reply, state.connected?, state}
  end

  def handle_info({VintageNet, @wlan0_property, _old, :internet, _metadata}, _state) do
    NameBadge.Device.re_render(:partial)
    {:noreply, %{connected?: true}}
  end

  def handle_info(:connect, state) do
    Circuits.GPIO.open("WIFI_EN", :output, initial_value: 0)
    {:noreply, state}
  end
end
