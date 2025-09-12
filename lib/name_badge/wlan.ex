defmodule NameBadge.Wlan do
  @moduledoc """
  Handles changes in the WiFi/WLAN connection.
  """

  use GenServer

  @wlan0_property ["interface", "wlan0", "connection"]

  def init(_args) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  # Callbacks

  def start_link(_args) do
    VintageNet.subscribe(@wlan0_property)

    # Connect to the WiFi with a 2s delay
    Process.send_after(self(), :connect, :timer.seconds(2))

    {:ok, nil}
  end

  def handle_info({VintageNet, @wlan0_property, _old, :internet, _metadata}, state) do
    schedule_render(:partial)
    {:noreply, state}
  end

  def handle_info(:connect, state) do
    Circuits.GPIO.open("WIFI_EN", :output, initial_value: 0)
    {:noreply, state}
  end
end
