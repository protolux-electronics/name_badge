defmodule NameBadge.ButtonMonitor do
  use GenServer

  alias Circuits.GPIO

  require Logger

  @long_press_timeout 500

  def send_button_press(which_button, press_type) do
    Registry.dispatch(NameBadge.Registry, which_button, fn pids ->
      for {pid, _value} <- pids, do: send(pid, {:button_event, which_button, press_type})
    end)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def subscribe(button_name),
    do: Registry.register(NameBadge.Registry, button_name, nil)

  def unsubscribe(button_name), do: Registry.unregister(NameBadge.Registry, button_name)

  @impl GenServer
  def init(opts) do
    {:ok, uart} = Circuits.UART.start_link()
    port = Keyword.fetch!(opts, :port)
    :ok = Circuits.UART.open(uart, port, speed: 115_200, active: true)

    timers = %{
      button_1: nil,
      button_2: nil,
      button_3: nil
    }

    {:ok, %{uart: uart, timers: timers}}
  end

  @impl GenServer
  def handle_info({:circuits_uart, _port, data}, state) do
    state =
      case parse_button_event(data) do
        {button_id, :down} ->
          Logger.info("#{button_id} down")

          if not is_nil(state.timers[button_id]) do
            :timer.cancel(state.timers[button_id])
          end

          {:ok, tid} = :timer.send_after(@long_press_timeout, {:button_timeout, button_id})
          put_in(state, [:timers, button_id], tid)

        {button_id, :up} ->
          Logger.warning("#{button_id} up")

          if not is_nil(state.timers[button_id]) do
            {:ok, :cancel} = :timer.cancel(state.timers[button_id])
            send_button_press(button_id, :single_press)
            Logger.info("#{button_id} single press")
          end

          put_in(state, [:timers, button_id], nil)
      end

    {:noreply, state}
  end

  def handle_info({:button_timeout, button_id}, state) do
    if not is_nil(state.timers[button_id]) do
      :timer.cancel(state.timers[button_id])
    end

    Logger.info("#{button_id} long press")

    send_button_press(button_id, :long_press)

    state = put_in(state, [:timers, button_id], nil)

    {:noreply, state}
  end

  defp parse_button_event(<<2, 7, 2, 1, 0>>), do: {:button_1, :down}
  defp parse_button_event(<<2, 7, 1, 1, 0>>), do: {:button_1, :up}
  defp parse_button_event(<<4, 7, 1, 1, 0>>), do: {:button_2, :down}
  defp parse_button_event(<<3, 7, 1, 1, 0>>), do: {:button_2, :up}
  defp parse_button_event(<<4, 7, 2, 1, 0>>), do: {:button_3, :down}
  defp parse_button_event(<<3, 7, 2, 1, 0>>), do: {:button_3, :up}
  defp parse_button_event(_other), do: :error
end
