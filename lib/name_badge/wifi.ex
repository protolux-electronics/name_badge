# defmodule NameBadge.Wifi do
#   alias VintageNet.PowerManager

#   @behaviour PowerManager

#   @impl PowerManager
#   def init(init_arg) do
#     {:ok, Map.new(init_arg)}
#   end

#   @impl PowerManager
#   def power_on(state) do
#     pull_down(state)
#     {:ok, state, :timer.minutes(2)}
#   end

#   @impl PowerManager
#   def start_powering_off(state) do
#     {:ok, state, :timer.seconds(2)}
#   end

#   @impl PowerManager
#   def power_off(state) do
#     {:ok, state, :timer.seconds(2)}
#   end

#   def pull_down(state) do
#     :ok = Circuits.GPIO.write_one(state.gpio, 0)
#   end
# end
