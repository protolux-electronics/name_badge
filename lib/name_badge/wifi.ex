defmodule NameBadge.Wifi do
  alias VintageNet.PowerManager

  @behaviour PowerManager

  @impl PowerManager
  def init(init_arg) do
    {:ok, Map.new(init_arg)}
  end

  @impl PowerManager
  def power_on(state) do
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

  def pull_down(state) do
    :ok = Circuits.GPIO.write_one(state.gpio, 0)
  end

  if Mix.target() == :host do
    def subscribe(_wlan_property) do
      :noop
    end
  else
    def subscribe(wlan_property) do
      VintageNet.subscribe(wlan_property)
    end
  end

  if Mix.target() == :host do
    def connected?(_wlan_property) do
      :noop
    end
  else
    def connected?(wlan_property) do
      VintageNet.get(wlan_property) == :internet
    end
  end
end
